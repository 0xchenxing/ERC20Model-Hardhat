// SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "../library/AdvancedERC20.sol";

// contract TestToken is AdvancedERC20 {
//     constructor(
//         string memory name_,
//         string memory symbol_,
//         uint256 initialSupply_,
//         uint256 initialTransferFee_,
//         address initialFeeRecipient_,
//         address initialOwner
//     ) AdvancedERC20(
//         name_,
//         symbol_,
//         initialSupply_,
//         initialTransferFee_,
//         initialFeeRecipient_,
//         initialOwner
//     ) {}

//     // 提供一个方法来铸造代币用于测试
//     function mint(address to, uint256 amount) external onlyOwner {
//         _mint(to, amount);
//     }
// }


pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract TestERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}