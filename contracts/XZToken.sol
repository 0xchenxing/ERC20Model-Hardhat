// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./library/AdvancedERC20.sol";

/**
 * @title XZToken
 * @dev XZToken合约实现，继承AdvancedERC20增强版ERC20功能
 * 支持手续费、裂变关系和销毁功能
 */
contract XZToken is AdvancedERC20 {
    
    /**
     * @dev 构造函数
     * 代币名称：XZToken
     * 代币符号：XZ
     * 初始供应量：2100万 XZ
     * 初始手续费：0%
     * 初始手续费接收地址：部署者地址
     * 初始拥有者：部署者地址
     */
    constructor() AdvancedERC20(
        "XZToken",                    // 代币名称
        "XZ",                        // 代币符号
        21000000 * 10**18,           // 初始供应量（2100万 XZ，考虑18位小数）
        0,                           // 初始手续费率（0%，基点）
        msg.sender,                  // 初始手续费接收地址
        msg.sender                   // 初始合约所有者
    ) {
        // AdvancedERC20 构造函数会自动处理所有初始化
        // 可以在这里添加额外的初始化逻辑
    }
}