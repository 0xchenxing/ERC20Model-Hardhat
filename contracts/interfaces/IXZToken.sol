// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IXZToken
 * @dev XZToken合约的接口定义，用于战略销毁功能
 */
interface IXZToken {
    /**
     * @dev 通过预言机触发战略销毁
     * @param amount 要销毁的代币数量
     */
    function burnStrategicViaOracle(uint256 amount) external;
}