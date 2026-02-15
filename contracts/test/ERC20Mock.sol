// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20Mock
 * @dev 用于测试的ERC20代币模拟合约
 */
contract ERC20Mock is ERC20 {
    /**
     * @dev 构造函数
     * @param name 代币名称
     * @param symbol 代币符号
     * @param initialSupply 初始供应量
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev 允许任何人铸造代币（仅用于测试）
     * @param to 接收地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @dev 允许任何人燃烧代币（仅用于测试）
     * @param from 燃烧地址
     * @param amount 燃烧数量
     */
    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}
