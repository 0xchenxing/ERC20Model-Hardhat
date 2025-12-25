// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title XZToken
 * @dev XZToken合约实现，满足DataReceiverAndPumper测试需求
 * 包含ERC20标准功能和销毁功能
 */
contract XZToken is ERC20, ERC20Burnable, Ownable {
    
    /**
     * @dev 构造函数
     * 代币名称：XZToken
     * 代币符号：XZ
     * 初始供应量：2100万 XZ
     * 初始拥有者：合约部署者
     */
    constructor() ERC20("XZToken", "XZ") Ownable(msg.sender) {
        // 铸造初始供应量给拥有者（2100万 XZ，考虑18位小数）
        _mint(msg.sender, 21000000 * 10**18);
    }
    
    /**
     * @dev 铸造新代币（仅用于测试）
     * @param to 接收地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}