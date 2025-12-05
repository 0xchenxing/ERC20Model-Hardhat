// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ITokenLockVault
 * @dev TokenLockVault合约的接口定义
 * 包含所有公共函数、事件、枚举和结构体的声明
 */
interface ITokenLockVault {
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
        IERC20 token;
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 startTime;
        uint256 releaseCount;
        uint256 totalPeriods;
        address beneficiary;
        ReleaseMode mode;
        bool isActive;
        bytes description;
    }
    
    // 事件声明
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
    

    
    // 权限控制函数
    function setOperator(address operator, bool status) external;
    
    // 锁仓创建函数
    function lockForSelf(
        address tokenAddress,
        uint256 amount,
        ReleaseMode mode,
        uint256 totalPeriods,
        bytes memory description
    ) external returns (uint256);
    
    function lockForOther(
        address beneficiary,
        address tokenAddress,
        uint256 amount,
        ReleaseMode mode,
        uint256 totalPeriods,
        bytes memory description
    ) external returns (uint256);
    
    // 代币释放函数
    function release(uint256 lockId) external;
    function batchRelease(uint256[] memory lockIds) external;
    function releaseAll() external;
    
    // 查询函数
    function getReleasableAmount(uint256 lockId) external view returns (uint256, uint256);
    function getUserLocks(address user) external view returns (LockRecord[] memory);
    function getLockInfo(uint256 lockId) external view returns (
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
    );
    function getUserLockStats(address user) external view returns (
        uint256 totalLocked,
        uint256 totalReleased,
        uint256 activeLocks
    );
    
    // 公共getter函数
    function locks(uint256) external view returns (LockRecord memory);
    function userLocks(address) external view returns (uint256[] memory);
    function operators(address) external view returns (bool);
    function owner() external view returns (address);
}