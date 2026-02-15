// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title 质押生息合约 (独立奖励池设计)
 * @notice 奖励池与质押池完全分离，用户质押时选择奖励代币
 */
contract StakingVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====== 1. 质押模式管理器 ======
    struct StakingMode {
        uint256 duration;      // 锁仓时长（秒）
        uint256 multiplier;    // 奖励乘数（100 = 1倍）
        uint256 penaltyBps;    // 提前赎回惩罚（基点，100 = 1%）
        string name;           // 模式名称
        bool enabled;
    }
    StakingMode[] public stakingModes;

    // ====== 2. 独立奖励池管理 ======
    struct RewardPool {
        uint256 totalRewards;  // 奖励池总量
        uint256 annualRewardPerToken; // 每年每1个完整代币的奖励
        uint256 lastUpdateTime; // 上次更新时间
        uint256 totalDistributed; // 已发放总量
        bool enabled;          // 是否启用
    }
    mapping(IERC20 => RewardPool) public rewardPools;
    IERC20[] public allRewardTokens;

    // ====== 3. 质押池核心状态 ======
    struct Pool {
        IERC20 stakingToken;
        uint256 totalStaked;
        uint256 lastUpdateTime;
    }
    mapping(IERC20 => Pool) public pools;
    IERC20[] public allStakingTokens;

    // ====== 4. 用户质押记录 ======
    struct UserStake {
        IERC20 stakingToken;
        IERC20 rewardToken;    // 用户选择的奖励代币
        uint256 amount;
        uint256 modeId;
        uint256 stakeTime;
        uint256 unlockTime;
        uint256 rewardDebt;    // 已领取的奖励
    }
    // 用于外部视图的简化结构
    struct UserStakeInfo {
        IERC20 stakingToken;
        IERC20 rewardToken;
        uint256 amount;
        uint256 modeId;
        uint256 stakeTime;
        uint256 unlockTime;
    }
    mapping(address => UserStake[]) public userStakes;

    // ====== 事件 ======
    event Staked(address indexed user, IERC20 indexed stakingToken, IERC20 indexed rewardToken, uint256 amount, uint256 modeId, uint256 unlockTime);
    event Unstaked(address indexed user, IERC20 indexed stakingToken, uint256 principal, uint256 reward, uint256 penalty, bool early);
    event RewardClaimed(address indexed user, IERC20 indexed rewardToken, uint256 amount);
    event RewardPoolAdded(IERC20 indexed rewardToken, uint256 totalRewards, uint256 annualRewardPerToken);
    event RewardPoolFunded(IERC20 indexed rewardToken, uint256 amount);
    event PoolAdded(IERC20 indexed stakingToken);

    constructor() Ownable(msg.sender) {
        // 初始化三种质押模式
        stakingModes.push(StakingMode({
            duration: 30 days,
            multiplier: 120,
            penaltyBps: 1000,
            name: unicode"模式A: 30天",
            enabled: true
        }));
        stakingModes.push(StakingMode({
            duration: 90 days,
            multiplier: 150,
            penaltyBps: 2000,
            name: unicode"模式B: 90天",
            enabled: true
        }));
        stakingModes.push(StakingMode({
            duration: 180 days,
            multiplier: 200,
            penaltyBps: 3000,
            name: unicode"模式C: 180天",
            enabled: true
        }));
    }

    // ====== 5. 核心用户接口 ======

    /**
     * @dev 用户质押，并选择奖励代币
     */
    function stake(
        IERC20 _stakingToken,
        uint256 _amount,
        uint256 _modeId,
        IERC20 _rewardToken
    ) external nonReentrant {
        require(_amount > 0, "Amount zero");
        require(_modeId < stakingModes.length && stakingModes[_modeId].enabled, "Invalid mode");
        require(address(pools[_stakingToken].stakingToken) != address(0), "Pool not exists");
        require(rewardPools[_rewardToken].enabled, "Reward pool not exists or disabled");

        StakingMode memory mode = stakingModes[_modeId];

        // 1. 转移质押代币
        _stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        // 2. 更新质押池
        Pool storage pool = pools[_stakingToken];
        pool.totalStaked += _amount;
        pool.lastUpdateTime = block.timestamp;

        // 3. 创建用户记录
        UserStake memory newStake = UserStake({
            stakingToken: _stakingToken,
            rewardToken: _rewardToken,
            amount: _amount,
            modeId: _modeId,
            stakeTime: block.timestamp,
            unlockTime: block.timestamp + mode.duration,
            rewardDebt: 0
        });
        userStakes[msg.sender].push(newStake);

        emit Staked(msg.sender, _stakingToken, _rewardToken, _amount, _modeId, newStake.unlockTime);
    }

    /**
     * @dev 用户赎回
     */
    function unstake(uint256 _stakeIndex) external nonReentrant {
        UserStake storage userStake = userStakes[msg.sender][_stakeIndex];
        require(userStake.amount > 0, "Stake not exist");

        Pool storage pool = pools[userStake.stakingToken];
        StakingMode memory mode = stakingModes[userStake.modeId];

        // 1. 计算奖励
        uint256 pendingReward = _calculateReward(msg.sender, _stakeIndex);
        if (pendingReward > 0) {
            userStake.rewardToken.safeTransfer(msg.sender, pendingReward);
            RewardPool storage rewardPool = rewardPools[userStake.rewardToken];
            rewardPool.totalDistributed += pendingReward;
            emit RewardClaimed(msg.sender, userStake.rewardToken, pendingReward);
        }

        // 2. 处理本金与惩罚
        bool isEarly = block.timestamp < userStake.unlockTime;
        uint256 penalty = 0;
        uint256 principalToReturn = userStake.amount;

        if (isEarly) {
            penalty = (userStake.amount * mode.penaltyBps) / 10000;
            principalToReturn = userStake.amount - penalty;
        }

        // 3. 返还本金
        userStake.stakingToken.safeTransfer(msg.sender, principalToReturn);
        pool.totalStaked -= userStake.amount;

        // 4. 清理记录
        delete userStakes[msg.sender][_stakeIndex];

        emit Unstaked(msg.sender, userStake.stakingToken, principalToReturn, pendingReward, penalty, isEarly);
    }

    /**
     * @dev 领取奖励
     */
    function claimRewards(uint256 _stakeIndex) external nonReentrant {
        UserStake storage userStake = userStakes[msg.sender][_stakeIndex];
        require(userStake.amount > 0, "Stake not exist");

        // 计算奖励
        uint256 pendingReward = _calculateReward(msg.sender, _stakeIndex);
        require(pendingReward > 0, "No rewards to claim");

        // 发放奖励
        userStake.rewardToken.safeTransfer(msg.sender, pendingReward);
        
        // 更新奖励池
        RewardPool storage rewardPool = rewardPools[userStake.rewardToken];
        rewardPool.totalDistributed += pendingReward;
        
        // 更新用户奖励债务
        userStake.rewardDebt += pendingReward;

        emit RewardClaimed(msg.sender, userStake.rewardToken, pendingReward);
    }

    // ====== 6. 管理员接口 ======

    // 添加质押池
    function addStakingPool(IERC20 _stakingToken) external onlyOwner {
        require(address(pools[_stakingToken].stakingToken) == address(0), "Pool exists");
        pools[_stakingToken] = Pool({
            stakingToken: _stakingToken,
            totalStaked: 0,
            lastUpdateTime: block.timestamp
        });
        allStakingTokens.push(_stakingToken);
        emit PoolAdded(_stakingToken);
    }

    // 添加奖励池
    function addRewardPool(IERC20 _rewardToken, uint256 _totalRewards, uint256 _annualRewardPerToken) external onlyOwner {
        require(!rewardPools[_rewardToken].enabled, "Reward pool already exists");
        require(_totalRewards > 0, "Total rewards must be greater than 0");
        require(_annualRewardPerToken > 0, "Annual reward per token must be greater than 0");
        require(_annualRewardPerToken <= _totalRewards, "Annual reward per token cannot exceed total rewards");
        
        // 转移奖励代币到合约
        _rewardToken.safeTransferFrom(msg.sender, address(this), _totalRewards);
        
        // 创建奖励池
        rewardPools[_rewardToken] = RewardPool({
            totalRewards: _totalRewards,
            annualRewardPerToken: _annualRewardPerToken,
            lastUpdateTime: block.timestamp,
            totalDistributed: 0,
            enabled: true
        });
        allRewardTokens.push(_rewardToken);
        
        emit RewardPoolAdded(_rewardToken, _totalRewards, _annualRewardPerToken);
    }

    // 为奖励池充值
    function fundRewardPool(IERC20 _rewardToken, uint256 _amount) external onlyOwner {
        require(rewardPools[_rewardToken].enabled, "Reward pool not exists or disabled");
        
        // 转移奖励代币到合约
        _rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        // 更新奖励池
        RewardPool storage rewardPool = rewardPools[_rewardToken];
        rewardPool.totalRewards += _amount;
        
        emit RewardPoolFunded(_rewardToken, _amount);
    }

    // ====== 7. 内部核心逻辑 ======

    // 计算用户奖励
    function _calculateReward(address _user, uint256 _stakeIndex) internal view returns (uint256) {
        UserStake storage userStake = userStakes[_user][_stakeIndex];
        if (userStake.amount == 0) return 0;
        
        RewardPool storage rewardPool = rewardPools[userStake.rewardToken];
        StakingMode memory mode = stakingModes[userStake.modeId];
        
        // 计算质押时间
        uint256 stakeDuration = block.timestamp - userStake.stakeTime;
        if (stakeDuration > mode.duration) {
            stakeDuration = mode.duration;
        }
        
        // 计算应得奖励：
        // 1. 直接使用wei单位的质押量
        // 2. annualRewardPerToken表示每年每1e18 wei的奖励
        // 3. 乘以质押时间（转换为年）
        // 4. 应用奖励乘数
        uint256 baseReward;
        
        // 统一使用比例计算奖励，提高精度
        // annualRewardPerToken是每年每1e18 wei的奖励，所以直接用userStake.amount计算
        baseReward = (stakeDuration * rewardPool.annualRewardPerToken * userStake.amount) / (365 * 24 * 60 * 60 * 1e18);
        
        uint256 multipliedReward = (baseReward * mode.multiplier) / 100;
        
        // 减去已领取的奖励
        uint256 pendingReward = multipliedReward - userStake.rewardDebt;
        
        // 确保不超过奖励池剩余量
        uint256 remainingRewards = rewardPool.totalRewards - rewardPool.totalDistributed;
        if (pendingReward > remainingRewards) {
            pendingReward = remainingRewards;
        }
        
        return pendingReward;
    }

    // ====== 8. 查询函数 ======
    function getUserStakes(address _user) external view returns (UserStakeInfo[] memory) {
        uint256 stakeCount = userStakes[_user].length;
        UserStakeInfo[] memory stakesInfo = new UserStakeInfo[](stakeCount);
        
        for (uint i = 0; i < stakeCount; i++) {
            UserStake storage userStakeItem = userStakes[_user][i];
            stakesInfo[i] = UserStakeInfo({
                stakingToken: userStakeItem.stakingToken,
                rewardToken: userStakeItem.rewardToken,
                amount: userStakeItem.amount,
                modeId: userStakeItem.modeId,
                stakeTime: userStakeItem.stakeTime,
                unlockTime: userStakeItem.unlockTime
            });
        }
        return stakesInfo;
    }
    
    function getAvailableRewardTokens() external view returns (IERC20[] memory) {
        return allRewardTokens;
    }
    
    function getRewardPoolInfo(IERC20 _rewardToken) external view returns (
        uint256 totalRewards,
        uint256 annualRewardPerToken,
        uint256 totalDistributed,
        uint256 remainingRewards
    ) {
        RewardPool storage rewardPool = rewardPools[_rewardToken];
        totalRewards = rewardPool.totalRewards;
        annualRewardPerToken = rewardPool.annualRewardPerToken;
        totalDistributed = rewardPool.totalDistributed;
        remainingRewards = totalRewards - totalDistributed;
    }
}
