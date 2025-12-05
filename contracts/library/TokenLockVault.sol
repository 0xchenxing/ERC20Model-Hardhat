// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TokenLockVault
 * @dev ERC20代币锁仓库合约，支持多种释放模式（日、周、月、季、年）
 * 提供锁仓、释放、撤销等功能，可用于代币分发、团队激励等场景
 */
contract TokenLockVault is Ownable {
    // 释放模式枚举
    enum ReleaseMode {
        Daily,
        Weekly,
        Monthly,
        Quarterly,
        Yearly
    }
    
    // 锁仓记录结构体
    struct LockRecord {
        IERC20 token;             // 代币合约地址（20字节）
        uint256 totalAmount;      // 总锁仓金额（32字节）
        uint256 releasedAmount;   // 已释放金额（32字节）
        uint256 startTime;        // 开始时间（32字节）
        uint256 releaseCount;     // 已释放次数（32字节）
        uint256 totalPeriods;     // 总释放期数（32字节）
        address beneficiary;      // 受益人地址 (20字节)
        ReleaseMode mode;         // 释放模式 (1字节，enum实际存储为uint8)
        bool isActive;            // 是否活跃 (1字节)
        bytes description;        // 锁仓说明（使用bytes替代string）
    }
    
    // 事件
    event LockCreated(
        uint256 indexed lockId,
        address indexed beneficiary,
        address token,
        uint256 amount,
        ReleaseMode mode,
        uint256 totalPeriods,
        bytes description,
        address locker
    );
    
    event TokensReleased(
        uint256 indexed lockId,
        address indexed beneficiary,
        uint256 amount,
        uint256 releaseTime
    );
    
    event LockRevoked(
        uint256 indexed lockId,
        address indexed revoker,
        uint256 remainingAmount
    );
    
    // 锁仓记录映射
    mapping(uint256 => LockRecord) public locks;
    mapping(address => uint256[]) public userLocks;
    
    // 锁仓ID计数器
    uint256 private _lockIdCounter;
    
    // 权限控制
    mapping(address => bool) public operators;
    

    
    /**
     * @dev 构造函数
     * @param initialOwner 初始所有者地址
     */
    constructor(address initialOwner) Ownable(initialOwner) {}
    
    modifier onlyOperator() {
        require(msg.sender == owner() || operators[msg.sender], "Not operator");
        _;
    }
    
    /**
     * @dev 设置操作员
     * @param operator 要设置的操作员地址
     * @param status 操作员状态：true为设置，false为取消
     */
    function setOperator(address operator, bool status) external onlyOwner {
        operators[operator] = status;
    }
    
    /**
     * @dev 为自己创建锁仓
     * @param tokenAddress 代币地址
     * @param amount 锁仓金额
     * @param mode 释放模式
     * @param totalPeriods 总释放期数
     * @param description 锁仓说明
     * @return lockId 创建的锁仓ID
     */
    function lockForSelf(
        address tokenAddress,
        uint256 amount,
        ReleaseMode mode,
        uint256 totalPeriods,
        bytes memory description
    ) external returns (uint256) {
        return _createLock(msg.sender, msg.sender, tokenAddress, amount, mode, totalPeriods, description);
    }
    
    /**
     * @dev 为第三方创建锁仓
     * @param beneficiary 受益人地址
     * @param tokenAddress 代币地址
     * @param amount 锁仓金额
     * @param mode 释放模式
     * @param totalPeriods 总释放期数
     * @param description 锁仓说明
     * @return lockId 创建的锁仓ID
     */
    function lockForOther(
        address beneficiary,
        address tokenAddress,
        uint256 amount,
        ReleaseMode mode,
        uint256 totalPeriods,
        bytes memory description
    ) external onlyOperator returns (uint256) {
        return _createLock(msg.sender, beneficiary, tokenAddress, amount, mode, totalPeriods, description);
    }
    
    /**
     * @dev 创建锁仓记录（内部函数）
     * @param locker 锁仓发起者地址
     * @param beneficiary 受益人地址
     * @param tokenAddress 代币地址
     * @param amount 锁仓金额
     * @param mode 释放模式
     * @param totalPeriods 总释放期数
     * @param description 锁仓说明
     * @return lockId 创建的锁仓ID
     */
    function _createLock(
        address locker,
        address beneficiary,
        address tokenAddress,
        uint256 amount,
        ReleaseMode mode,
        uint256 totalPeriods,
        bytes memory description
    ) internal returns (uint256) {
        require(amount > 0, "Amount must be positive");
        require(beneficiary != address(0), "Invalid beneficiary");
        require(totalPeriods > 0, "Total periods must be positive");
        require(tokenAddress != address(0), "Invalid token address");
        
        // 转移代币到合约
        require(IERC20(tokenAddress).transferFrom(locker, address(this), amount), "Token transfer failed");
        
        uint256 lockId = _lockIdCounter++;
        
        locks[lockId] = LockRecord({
            token: IERC20(tokenAddress),
            beneficiary: beneficiary,
            totalAmount: amount,
            releasedAmount: 0,
            startTime: block.timestamp,
            releaseCount: 0,
            mode: mode,
            description: description,
            isActive: true,
            totalPeriods: totalPeriods
        });
        
        userLocks[beneficiary].push(lockId);
        
        emit LockCreated(lockId, beneficiary, tokenAddress, amount, mode, totalPeriods, description, locker);
        
        return lockId;
    }
    
    /**
     * @dev 释放代币
     * @param lockId 锁仓ID
     */
    function release(uint256 lockId) external virtual {
        LockRecord storage lock = locks[lockId];
        require(lock.isActive, "Lock not active");
        require(lock.beneficiary == msg.sender, "Not beneficiary");
        
        (uint256 releasableAmount, uint256 releasePeriods) = getReleasableAmount(lockId);
        require(releasableAmount > 0, "No tokens to release");
        
        // 更新锁仓记录
        lock.releasedAmount += releasableAmount;
        lock.releaseCount += releasePeriods;
        
        // 如果已全部释放，标记为非活跃
        if (lock.releasedAmount >= lock.totalAmount) {
            lock.isActive = false;
        }
        
        // 转移代币给受益人
        require(lock.token.transfer(lock.beneficiary, releasableAmount), "Token transfer failed");
        
        emit TokensReleased(lockId, lock.beneficiary, releasableAmount, block.timestamp);
    }
    
    /**
     * @dev 批量释放代币
     * @param lockIds 锁仓ID数组
     */
    function batchRelease(uint256[] memory lockIds) external {
        for (uint256 i = 0; i < lockIds.length; i++) {
            LockRecord storage lock = locks[lockIds[i]];
            if (!lock.isActive || lock.beneficiary != msg.sender) {
                continue;
            }
            
            (uint256 releasableAmount, uint256 releasePeriods) = getReleasableAmount(lockIds[i]);
            if (releasableAmount > 0) {
                // 更新锁仓记录
                lock.releasedAmount += releasableAmount;
                lock.releaseCount += releasePeriods;
                
                // 转移代币给受益人
                require(lock.token.transfer(msg.sender, releasableAmount), "Token transfer failed");
                
                // 如果已全部释放，标记为非活跃
                if (lock.releasedAmount >= lock.totalAmount) {
                    lock.isActive = false;
                }
                
                emit TokensReleased(lockIds[i], msg.sender, releasableAmount, block.timestamp);
            }
        }
    }
    
    /**
     * @dev 一键释放用户所有可释放的代币
     * 自动查找用户所有锁仓，释放所有符合条件的代币
     */
    function releaseAll() external {
        uint256[] memory userLockIds = userLocks[msg.sender];
        
        for (uint256 i = 0; i < userLockIds.length; i++) {
            uint256 lockId = userLockIds[i];
            LockRecord storage lock = locks[lockId];
            
            // 跳过非活跃或非受益人的锁仓
            if (!lock.isActive || lock.beneficiary != msg.sender) {
                continue;
            }
            
            // 获取可释放金额
            (uint256 releasableAmount, uint256 releasePeriods) = getReleasableAmount(lockId);
            
            // 如果有可释放金额，执行释放
            if (releasableAmount > 0) {
                // 更新锁仓记录
                lock.releasedAmount += releasableAmount;
                lock.releaseCount += releasePeriods;
                
                // 执行转账
                require(lock.token.transfer(msg.sender, releasableAmount), "Token transfer failed");
                
                // 如果已全部释放，标记为非活跃
                if (lock.releasedAmount >= lock.totalAmount) {
                    lock.isActive = false;
                }
                
                emit TokensReleased(lockId, msg.sender, releasableAmount, block.timestamp);
            }
        }
    }
    
    /**
     * @dev 计算可释放金额
     * @param lockId 锁仓ID
     * @return amount 可释放金额
     * @return periods 可释放期数
     */
    function getReleasableAmount(uint256 lockId) public view virtual returns (uint256 amount, uint256 periods) {
        LockRecord memory lock = locks[lockId];
        if (!lock.isActive) {
            return (0, 0);
        }
        
        uint256 timePassed = block.timestamp - lock.startTime;
        uint256 periodLength = _getPeriodLength(lock.mode);
        
        // 计算应该释放的期数
        uint256 periodsPassed = timePassed / periodLength;
        uint256 periodsToRelease = periodsPassed > lock.releaseCount ? periodsPassed - lock.releaseCount : 0;
        
        if (periodsToRelease == 0) {
            return (0, 0);
        }
        
        // 确保不会超额释放
        if (lock.releaseCount + periodsToRelease > lock.totalPeriods) {
            periodsToRelease = lock.totalPeriods - lock.releaseCount;
        }
        
        uint256 periodAmount = lock.totalAmount / lock.totalPeriods;
        amount = periodAmount * periodsToRelease;
        
        // 最后一期处理余数
        if (lock.releaseCount + periodsToRelease >= lock.totalPeriods) {
            amount = lock.totalAmount - lock.releasedAmount;
        }
        
        return (amount, periodsToRelease);
    }
    
    /**
     * @dev 获取周期长度（秒）
     * @param mode 释放模式
     * @return length 周期长度（秒）
     */
    function _getPeriodLength(ReleaseMode mode) internal pure virtual returns (uint256) {
        if (mode == ReleaseMode.Daily) {
            return 1 days;
        } else if (mode == ReleaseMode.Weekly) {
            return 7 days; // 一周7天
        } else if (mode == ReleaseMode.Monthly) {
            return 30 days; // 简化为30天一个月
        } else if (mode == ReleaseMode.Quarterly) {
            return 91 days; // 约一个季度
        } else { // Yearly
            return 365 days;
        }
    }
    
    /**
     * @dev 获取用户的锁仓记录
     * @param user 用户地址
     * @return locks 用户的锁仓记录数组
     */
    function getUserLocks(address user) external view virtual returns (LockRecord[] memory) {
        uint256[] memory lockIds = userLocks[user];
        LockRecord[] memory userLockRecords = new LockRecord[](lockIds.length);
        
        for (uint256 i = 0; i < lockIds.length; i++) {
            userLockRecords[i] = locks[lockIds[i]];
        }
        
        return userLockRecords;
    }
    
    /**
     * @dev 获取锁仓信息
     * @param lockId 锁仓ID
     * @return beneficiary 受益人地址
     * @return totalAmount 总锁仓金额
     * @return releasedAmount 已释放金额
     * @return startTime 开始时间
     * @return releaseCount 已释放次数
     * @return mode 释放模式
     * @return totalPeriods 总释放期数
     * @return description 锁仓说明
     * @return isActive 是否活跃
     * @return nextReleaseTime 下次释放时间
     */
    function getLockInfo(uint256 lockId) external view virtual returns (
        address beneficiary,
        uint256 totalAmount,
        uint256 releasedAmount,
        uint256 startTime,
        uint256 releaseCount,
        ReleaseMode mode,
        uint256 totalPeriods,
        bytes memory description,
        bool isActive,
        uint256 nextReleaseTime
    ) {
        LockRecord memory lock = locks[lockId];
        uint256 periodLength = _getPeriodLength(lock.mode);
        
        uint256 nextRelease = lock.startTime + (lock.releaseCount + 1) * periodLength;
        if (lock.releaseCount >= lock.totalPeriods) {
            nextRelease = 0;
        }
        
        return (
            lock.beneficiary,
            lock.totalAmount,
            lock.releasedAmount,
            lock.startTime,
            lock.releaseCount,
            lock.mode,
            lock.totalPeriods,
            lock.description,
            lock.isActive,
            nextRelease
        );
    }
    
    /**
     * @dev 查询用户锁仓统计信息
     * @param user 用户地址
     * @return totalLocked 总锁仓量
     * @return totalReleased 已释放量
     * @return activeLocks 活跃锁仓数量
     */
    function getUserLockStats(address user) external view virtual returns (
        uint256 totalLocked,
        uint256 totalReleased,
        uint256 activeLocks
    ) {
        uint256[] memory lockIds = userLocks[user];
        
        for (uint256 i = 0; i < lockIds.length; i++) {
            LockRecord memory lock = locks[lockIds[i]];
            totalLocked += lock.totalAmount;
            totalReleased += lock.releasedAmount;
            if (lock.isActive) {
                activeLocks++;
            }
        }
        
        return (totalLocked, totalReleased, activeLocks);
    }
}