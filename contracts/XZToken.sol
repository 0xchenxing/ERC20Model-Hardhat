// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract XZToken is ERC20, ERC20Burnable, Ownable, ReentrancyGuard {
    // 总供应量，假设为2100万代币，18位小数
    uint256 public constant TOTAL_SUPPLY = 21_000_000 * 10**18;

    // 分配比例（基于总供应量）
    uint256 public constant SEED_ALLOCATION = TOTAL_SUPPLY * 10 / 100; // 种子期 10%
    uint256 public constant STRATEGIC_ROUND_ALLOCATION = TOTAL_SUPPLY * 10 / 100; // 战略轮 10%
    uint256 public constant STARTUP_INCENTIVE_ALLOCATION = TOTAL_SUPPLY * 5 / 100; // 初创激励 5%
    uint256 public constant ECOSYSTEM_INCENTIVE_ALLOCATION = TOTAL_SUPPLY * 30 / 100; // 生态激励 30%
    uint256 public constant STRATEGIC_RESERVE_ALLOCATION = TOTAL_SUPPLY * 20 / 100; // 战略储备 20%
    uint256 public constant LIQUIDITY_RESERVE_ALLOCATION = TOTAL_SUPPLY * 10 / 100; // 流动性储备 10%
    uint256 public constant PROJECT_ALLOCATION = TOTAL_SUPPLY * 15 / 100; // 项目方团队与顾问 15%

    // 时间戳和周期定义（以秒为单位，近似月为30天）
    uint256 public immutable deployTime;
    uint256 public constant MINUTE = 60 seconds; // 为了演示方便，使用分钟作为基本单位
    uint256 public constant HOUR = 60 minutes;   // 小时
    uint256 public constant DAY = 24 hours;      // 天

    // 各分配的默认释放参数
    uint256 public constant SEED_LOCK_PERIOD = 2 * MINUTE;         // 种子锁仓2分钟
    uint256 public constant SEED_RELEASE_PERIOD = 3 * MINUTE;      // 种子释放3分钟
    uint256 public constant STARTUP_RELEASE_PERIOD = 5 * MINUTE;   // 初创激励释放5分钟
    uint256 public constant STRATEGIC_ROUND_LOCK_PERIOD = 6 * MINUTE; // 战略轮锁仓6分钟（示例）
    uint256 public constant STRATEGIC_ROUND_RELEASE_PERIOD = 18 * MINUTE; // 战略轮线性释放18分钟（示例）
    uint256 public constant STRATEGIC_LOCK_PERIOD = 2 * MINUTE;    // 战略锁仓2分钟
    uint256 public constant STRATEGIC_RELEASE_PERIOD = 8 * MINUTE; // 战略释放8分钟
    uint256 public constant ECOSYSTEM_BURN_AFTER = 10 * MINUTE;    // 生态激励10分钟后销毁剩余
    uint256 public constant PROJECT_DEFAULT_LOCK_PERIOD = 1 * MINUTE;   // 默认锁仓1分钟
    uint256 public constant PROJECT_DEFAULT_RELEASE_PERIOD = 4 * MINUTE; // 默认释放4分钟

    // 剩余可分配量（用于vesting分配）
    mapping(string => uint256) public remainingAlloc;

    // Vesting结构
    struct Vesting {
        uint256 totalAmount; // 总vesting量
        uint256 released; // 已释放量
        uint256 start; // 释放开始时间
        uint256 duration; // 释放持续时间
    }

    mapping(string => mapping(address => Vesting)) public vestings; // 用户vesting数组

    string[] public vestingCategories = ["seed", "strategic_round", "project"];//项目方分配归属权分类

    // 初创激励池（空投）
    uint256 public airdropPool = STARTUP_INCENTIVE_ALLOCATION;
    uint256 public constant DAILY_AIRDROP_LIMIT = STARTUP_INCENTIVE_ALLOCATION / 10; // 减少空投期限为10个周期
    uint256 public constant DAILY_CLAIM_AMOUNT = 50 * 10**18; // 每个用户每次可领取50代币
    uint256 public lastAirdropDay; // 上次发放空投的日期（以天为单位）
    uint256 public dailyAirdropReleased; // 当天已发放的空投数量
    mapping(address => uint256) public lastClaimTime;
   
    // 生态激励池（质押，分佣）
    uint256 public ecosystemPool = ECOSYSTEM_INCENTIVE_ALLOCATION;

    // 添加多层推荐相关状态变量
    struct ReferralInfo {
        address referrer;      // 直接推荐人
        uint256 totalStaked;   // 用户团队总质押量
        uint256 totalRewards;  // 用户获得的总推荐奖励
    }

    // 推荐关系映射
    mapping(address => ReferralInfo) public referralInfo;
    mapping(address => address[]) public referrals; // 每个推荐人的下级列表

    // 多层推荐比例配置（百分比）
    uint256 public LEVEL1_RATE = 10;  // 第一级 10%
    uint256 public LEVEL2_RATE = 5;   // 第二级 5%  
    uint256 public LEVEL3_RATE = 2;   // 第三级 2%
    uint256 public constant MAX_REFERRAL_LEVELS = 3; // 最大推荐层级

    // 质押结构
    struct Stake {
        uint256 amount; // 质押金额
        uint256 startTime; // 开始时间
        uint256 lockPeriod; // 锁定期（秒）
        uint256 rewardDebt; // 已领取奖励
        // address referrer; // 推荐人
    }

    mapping(address => Stake[]) public stakes; // 用户质押数组
    uint256 public totalStaked; // 总质押量

    // 质押年化收益率（基点：3% = 300）
    uint256 public constant APY_7_DAYS = 300;
    uint256 public constant APY_30_DAYS = 600;
    uint256 public constant APY_90_DAYS = 1000;
    uint256 public constant APY_180_DAYS = 1500;
    uint256 public constant APY_360_DAYS = 2000;

    uint256 public constant EARLY_WITHDRAW_PENALTY = 20; // 提前赎回罚金 20%
    uint256 public constant REFERRAL_COMMISSION = 10; // 分佣比例 10%

    // 战略储备池
    uint256 public strategicPool = STRATEGIC_RESERVE_ALLOCATION;
    uint256 public strategicReleased;

    // 预言机地址（用于战略销毁）
    address public oracleAddress;

    // 事件
    event VestingAdded(address indexed beneficiary, uint256 amount, string category); // 添加vesting事件
    event VestingClaimed(address indexed user, uint256 amount, string category); // 领取vesting事件
    event AirdropClaimed(address indexed user, uint256 amount); // 空投领取事件
    event AirdropBurned(uint256 amount); // 空投销毁事件
    event Staked(address indexed user, uint256 amount, uint256 lockPeriod, address referrer); // 质押事件
    event Unstaked(address indexed user, uint256 amount, uint256 reward, uint256 penalty); // 赎回事件
    event RewardClaimed(address indexed user, uint256 reward); // 领取质押奖励事件
    event ReferralReward(address indexed referrer, uint256 reward); // 分佣推荐奖励事件
    event EcosystemBurned(uint256 amount); // 生态销毁事件
    event OracleSet(address oracle); // 设置预言机事件

    // 构造函数
    constructor(address projectOwner) ERC20("BaseToken", "BASE") Ownable(projectOwner) {
        deployTime = block.timestamp;
        _mint(address(this), TOTAL_SUPPLY);

        // 初始化剩余分配量
        remainingAlloc["seed"] = SEED_ALLOCATION;
        remainingAlloc["strategic_round"] = STRATEGIC_ROUND_ALLOCATION;
        remainingAlloc["project"] = PROJECT_ALLOCATION;

        // 初始非锁分配直接转给所有者（流动性储备）
        _transfer(address(this), projectOwner, LIQUIDITY_RESERVE_ALLOCATION);
    }

    // 设置预言机地址
    function setOracle(address _oracle) external onlyOwner {
        oracleAddress = _oracle;
        emit OracleSet(_oracle);
    }

    // 添加vesting（项目方为受益人添加，指定类别，对于project可自定义start和duration）
    function addVesting(string calldata category, address beneficiary, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be positive");
        require(remainingAlloc[category] >= amount, "Insufficient remaining allocation");

        // 检查该受益人是否已有种子期归属
        if (vestings[category][beneficiary].totalAmount == 0) {
            uint256 start;
            uint256 duration;

            if (keccak256(bytes(category)) == keccak256(bytes("seed"))) {
                start = deployTime + SEED_LOCK_PERIOD;
                duration = SEED_RELEASE_PERIOD;
            } else if (keccak256(bytes(category)) == keccak256(bytes("strategic_round"))) {
                start = deployTime + STRATEGIC_ROUND_LOCK_PERIOD;
                duration = STRATEGIC_ROUND_RELEASE_PERIOD;
            } else if (keccak256(bytes(category)) == keccak256(bytes("project"))) {
                start =  deployTime + PROJECT_DEFAULT_LOCK_PERIOD;
                duration = PROJECT_DEFAULT_RELEASE_PERIOD;
            } else {
                revert("Invalid category");
            }
            // 如果不存在，则初始化新的归属计划
            vestings[category][beneficiary] = Vesting({
                totalAmount: amount,
                released: 0,
                start: start,
                duration: duration
            });
        } else {
            // 如果已存在，则叠加归属代币数量
            vestings[category][beneficiary].totalAmount += amount;
        }

        remainingAlloc[category] -= amount;

        emit VestingAdded(beneficiary, amount, category);
    }

    // 计算用户单个vesting可领取的代币数量（线性释放）
    function calculateVestedAmount(Vesting storage vesting) internal view returns (uint256) {
        uint256 totalAmount = vesting.totalAmount;
        uint256 released = vesting.released;
        uint256 start = vesting.start;
        uint256 duration = vesting.duration;
        
        // 检查是否有归属
        if (totalAmount == 0) return 0;
        
        uint256 currentTime = block.timestamp;
        
        // 检查锁定期
        if (currentTime < start) {
            return 0; // 仍在锁定期，无可领取代币
        }
        
        // 计算锁定期结束后经过的时间
        uint256 elapsed = currentTime - start;
        
        // 如果已经超过归属期，可领取全部剩余代币
        if (elapsed >= duration) {
            return totalAmount - released;
        } else {
            // 按时间线性计算可领取的代币数量
            uint256 vested = totalAmount * elapsed / duration;
            return vested - released;
        }
    }

    // 计算用户所有vesting的总可领取量
    function getPendingVesting(address user) external view returns (uint256) {
        uint256 totalPending = 0;
        for(uint256 i = 0; i < vestingCategories.length; i++) {
            string storage category = vestingCategories[i];
            Vesting storage v = vestings[category][user];
            if (v.totalAmount > v.released) {
                uint256 releasable = calculateVestedAmount(v);
                if (releasable > 0) {
                    totalPending += releasable;
                }
            }
        }
        return totalPending;
    }

    // 用户一键领取所有vesting
    function claimAllVesting() external nonReentrant {
        uint256 totalReleasable = 0;
        for(uint256 i = 0; i < vestingCategories.length; i++) {
            string storage category = vestingCategories[i];
            Vesting storage v = vestings[category][msg.sender];
            if (v.totalAmount > v.released) {
                uint256 releasable = calculateVestedAmount(v);
                if (releasable > 0) {
                    v.released += releasable;
                    totalReleasable += releasable;
                    emit VestingClaimed(msg.sender, releasable, category);
                }
            }
        }
        require(totalReleasable > 0, "Nothing to release");
        _transfer(address(this), msg.sender, totalReleasable);
    }

    // 领取未分发种子部分（项目方领取剩余）
    function claimUnassignedSeed() external onlyOwner {
        require(block.timestamp >= deployTime + SEED_LOCK_PERIOD, "Not yet");
        uint256 amount = remainingAlloc["seed"];
        if (amount == 0) return;

        remainingAlloc["seed"] = 0;

        _transfer(address(this), owner(), amount);
        emit VestingClaimed(owner(), amount, "seed");
    }

    // 领取战略储备（项目方自主领取）
    function claimStrategic(uint256 amount) external onlyOwner nonReentrant {
        uint256 releaseStart = deployTime + STRATEGIC_LOCK_PERIOD;
        uint256 maxReleasable = calculateRelease(STRATEGIC_RESERVE_ALLOCATION, releaseStart, STRATEGIC_RELEASE_PERIOD, strategicReleased);
        require(amount <= maxReleasable, "Exceeds releasable");
        strategicReleased += amount;
        strategicPool -= amount;
        _transfer(address(this), owner(), amount);
        emit VestingClaimed(owner(), amount, "strategic");
    }

    // 向战略储备转入代币
    function depositStrategic(uint256 amount) external onlyOwner {
        _transfer(owner(), address(this), amount);
        strategicPool += amount;
        emit VestingAdded(owner(), amount, "strategic");
    }

    // 从战略储备销毁代币（项目方）
    function burnStrategic(uint256 amount) external onlyOwner {
        require(amount <= strategicPool, "Insufficient pool");
        strategicPool -= amount;
        _burn(address(this), amount);
        emit VestingClaimed(owner(), amount, "strategic_burn");
    }

    // 通过uniswap预言机合约销毁战略储备
    function burnStrategicViaOracle(uint256 amount) external {
        require(msg.sender == oracleAddress, "Only oracle");
        require(amount <= strategicPool, "Insufficient pool");
        strategicPool -= amount;
        _burn(address(this), amount);
    }

    // 计算线性释放量
    function calculateRelease(uint256 total, uint256 start, uint256 duration, uint256 released) internal view returns (uint256) {
        uint256 currentTime = block.timestamp;
        if (currentTime < start) return 0;
        uint256 elapsed = currentTime - start;
        if (elapsed >= duration) return total - released;
        return (total * elapsed / duration) - released;
    }

    // 领取空投
    function claimAirdrop() external nonReentrant {
        require(block.timestamp < deployTime + STARTUP_RELEASE_PERIOD, "Airdrop period ended");
        require(airdropPool > 0, "Airdrop pool empty");
        require(block.timestamp >= lastClaimTime[msg.sender] + 1 days, "Already claimed today");
        
        // 检查并更新每日空投限额
        uint256 currentDay = (block.timestamp - deployTime) / 1 days;
        if (currentDay > lastAirdropDay) {
            // 新的一天，重置当日发放量
            lastAirdropDay = currentDay;
            dailyAirdropReleased = 0;
        }
        
        uint256 amount = DAILY_CLAIM_AMOUNT;
        if (amount > airdropPool) {
            amount = airdropPool;
        }
        
        // 检查是否超过当日限额
        uint256 availableToday = DAILY_AIRDROP_LIMIT - dailyAirdropReleased;
        if (amount > availableToday) {
            amount = availableToday;
        }
        
        require(amount > 0, "No airdrop available today");
        
        lastClaimTime[msg.sender] = block.timestamp;
        dailyAirdropReleased += amount;
        airdropPool -= amount;
        _transfer(address(this), msg.sender, amount);
        emit AirdropClaimed(msg.sender, amount);
    }

    // 销毁剩余空投代币
    function burnRemainingAirdrop() external {
        require(block.timestamp >= deployTime + STARTUP_RELEASE_PERIOD, "Airdrop period not ended");
        uint256 amount = airdropPool;
        if (amount > 0) {
            airdropPool = 0;
            _burn(address(this), amount);
            emit AirdropBurned(amount);
        }
    }

    // 检查生态销毁（4年后烧剩余）
    function checkEcosystemBurn() internal {
        if (block.timestamp >= deployTime + ECOSYSTEM_BURN_AFTER && ecosystemPool > 0) {
            uint256 toBurn = ecosystemPool;
            ecosystemPool = 0;
            _burn(address(this), toBurn);
            emit EcosystemBurned(toBurn);
        }
    }

    // 质押函数
    function stake(uint256 amount, uint256 lockPeriodDays) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        require(lockPeriodDays == 7 || lockPeriodDays == 30 || lockPeriodDays == 90 || 
            lockPeriodDays == 180 || lockPeriodDays == 360, "Invalid lock period");

        _transfer(msg.sender, address(this), amount);
        totalStaked += amount;
        
        // 更新用户总质押量
        referralInfo[msg.sender].totalStaked += amount;
        
        // 更新推荐链路上的团队质押量
        address currentReferrer = referralInfo[msg.sender].referrer;
        for (uint256 i = 0; i < MAX_REFERRAL_LEVELS && currentReferrer != address(0); i++) {
            referralInfo[currentReferrer].totalStaked += amount;
            currentReferrer = referralInfo[currentReferrer].referrer;
        }

        stakes[msg.sender].push(Stake({
            amount: amount,
            startTime: block.timestamp,
            lockPeriod: lockPeriodDays * 1 days,
            rewardDebt: 0
        }));

        emit Staked(msg.sender, amount, lockPeriodDays, referralInfo[msg.sender].referrer);
    }

    // 获取APY
    function getApy(uint256 days_) internal pure returns (uint256) {
        if (days_ == 7) return APY_7_DAYS;
        if (days_ == 30) return APY_30_DAYS;
        if (days_ == 90) return APY_90_DAYS;
        if (days_ == 180) return APY_180_DAYS;
        return APY_360_DAYS;
    }

    // 计算单个stake的待领奖励
    function pendingReward(address user, uint256 index) public view returns (uint256) {
        Stake storage s = stakes[user][index];
        if (s.amount == 0) return 0;

        uint256 elapsed = block.timestamp - s.startTime;
        uint256 apy = getApy(s.lockPeriod / 1 days);
        uint256 reward = (s.amount * apy * elapsed) / (10000 * 365 days);

        return reward - s.rewardDebt;
    }

    // 计算用户所有stake的总待领奖励
    function getPendingRewards(address user) external view returns (uint256) {
        uint256 totalPending = 0;
        uint256 length = stakes[user].length;
        for (uint256 i = 0; i < length; i++) {
            totalPending += pendingReward(user, i);
        }
        return totalPending;
    }

     // 处理多层推荐奖励
    function _handleMultiLevelReferral(uint256 reward, address user) internal {
        address current = referralInfo[user].referrer;
        uint256[] memory rates = new uint256[](MAX_REFERRAL_LEVELS);
        rates[0] = LEVEL1_RATE;
        rates[1] = LEVEL2_RATE; 
        rates[2] = LEVEL3_RATE;
        
        for (uint256 i = 0; i < MAX_REFERRAL_LEVELS && current != address(0); i++) {
            uint256 refReward = reward * rates[i] / 100;
            
            if (ecosystemPool >= refReward) {
                ecosystemPool -= refReward;
                _transfer(address(this), current, refReward);
                
                // 更新推荐人奖励统计
                referralInfo[current].totalRewards += refReward;
                
                emit ReferralReward(current, refReward);
            }
            
            current = referralInfo[current].referrer;
        }
    }

    // 赎回质押（单个）
    function unstake(uint256 index) external nonReentrant {
        Stake storage s = stakes[msg.sender][index];
        require(s.amount > 0, "No stake");

        checkEcosystemBurn();

        // 先领取奖励
        uint256 reward = pendingReward(msg.sender, index);
        if (reward > 0) {
            s.rewardDebt += reward;
            require(ecosystemPool >= reward, "Insufficient pool");
            ecosystemPool -= reward;
            _transfer(address(this), msg.sender, reward);
            emit RewardClaimed(msg.sender, reward);

            // 多层推荐奖励
            _handleMultiLevelReferral(reward, msg.sender);
        }

        uint256 amount = s.amount;
        bool isEarly = block.timestamp < s.startTime + s.lockPeriod;
        uint256 penalty = 0;
        if (isEarly) {
            penalty = amount * EARLY_WITHDRAW_PENALTY / 100;
            amount -= penalty;
            _burn(address(this), penalty);
        }

        totalStaked -= s.amount;
        
        // 更新质押统计
        referralInfo[msg.sender].totalStaked -= s.amount;
        
        // 更新推荐链路上的团队质押量
        address currentReferrer = referralInfo[msg.sender].referrer;
        for (uint256 i = 0; i < MAX_REFERRAL_LEVELS && currentReferrer != address(0); i++) {
            referralInfo[currentReferrer].totalStaked -= s.amount;
            currentReferrer = referralInfo[currentReferrer].referrer;
        }
        
        s.amount = 0;
        _transfer(address(this), msg.sender, amount);
        emit Unstaked(msg.sender, amount, reward, penalty);
    }

    // 用户领取所有质押奖励
    function claimAllRewards() external nonReentrant {
        checkEcosystemBurn();

        uint256 totalReward = 0;
        uint256 length = stakes[msg.sender].length;
        for (uint256 i = 0; i < length; i++) {
            Stake storage s = stakes[msg.sender][i];
            if (s.amount > 0) {
                uint256 reward = pendingReward(msg.sender, i);
                if (reward > 0) {
                    s.rewardDebt += reward;
                    totalReward += reward;
                }
            }
        }
        
        require(totalReward > 0, "No reward");
        require(ecosystemPool >= totalReward, "Insufficient ecosystem pool");
        
        ecosystemPool -= totalReward;
        _transfer(address(this), msg.sender, totalReward);
        emit RewardClaimed(msg.sender, totalReward);

        // 多层推荐奖励
        _handleMultiLevelReferral(totalReward, msg.sender);
    }

    // 获取用户质押数量
    function getStakesCount(address user) external view returns (uint256) {
        return stakes[user].length;
    }

    // 设置推荐关系
    function setReferrer(address referrer) external {
        require(referrer != address(0), "Invalid referrer");
        require(referrer != msg.sender, "Cannot refer self");
        require(referralInfo[msg.sender].referrer == address(0), "Referrer already set");
        
        // 检查推荐关系循环
        address current = referrer;
        for (uint256 i = 0; i < MAX_REFERRAL_LEVELS; i++) {
            if (current == msg.sender) {
                revert("Circular referral detected");
            }
            current = referralInfo[current].referrer;
            if (current == address(0)) break;
        }
        
        referralInfo[msg.sender].referrer = referrer;
        referrals[referrer].push(msg.sender);
    }

    // 获取用户的推荐人
    function getReferrer(address user) public view returns (address) {
        return referralInfo[user].referrer;
    }

    // 获取用户的所有下级
    function getReferrals(address user) public view returns (address[] memory) {
        return referrals[user];
    }

    // 获取推荐网络统计
    function getReferralStats(address user) public view returns (
        uint256 directReferrals,
        uint256 totalTeamSize,
        uint256 teamTotalStaked,
        uint256 totalRewardsEarned
    ) {
        directReferrals = referrals[user].length;
        totalRewardsEarned = referralInfo[user].totalRewards;
        teamTotalStaked = referralInfo[user].totalStaked;
        
        // 计算团队总人数（包括间接推荐）
        address[] memory queue = new address[](100); // 简单队列
        uint256 front = 0;
        uint256 rear = 0;
        
        // 添加直接推荐人
        for (uint256 i = 0; i < directReferrals; i++) {
            queue[rear++] = referrals[user][i];
        }
        
        while (front < rear) {
            address current = queue[front++];
            totalTeamSize++;
            teamTotalStaked += referralInfo[current].totalStaked;
            
            // 添加当前用户的下级
            for (uint256 i = 0; i < referrals[current].length; i++) {
                if (rear < queue.length) {
                    queue[rear++] = referrals[current][i];
                }
            }
        }
    }

    // 管理员设置推荐关系（用于初始用户）
    function adminSetReferrer(address user, address referrer) external onlyOwner {
        require(referralInfo[user].referrer == address(0), "Referrer already set");
        require(user != referrer, "Cannot refer self");
        
        referralInfo[user].referrer = referrer;
        referrals[referrer].push(user);
    }

    // 更新推荐比例
    function updateReferralRates(uint256 level1, uint256 level2, uint256 level3) external onlyOwner {
        require(level1 + level2 + level3 <= 20, "Total rate too high"); // 限制总比例不超过20%
        LEVEL1_RATE = level1;
        LEVEL2_RATE = level2;
        LEVEL3_RATE = level3;
    }
}