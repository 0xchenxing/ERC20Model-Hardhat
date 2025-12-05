// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SecurityPool
 * @notice 独立的安全资金池，负责托管 BaseToken 的核心资金。
 *         只有 BaseToken 合约（控制者）可以提取资金，用于向外部用户付款或处理销毁。
 *         紧急情况下，控制者可以暂停资金池，阻止任何进一步的资金划转。
 */
contract SecurityPool is Ownable, Pausable, ReentrancyGuard {
    IERC20 public immutable token;
    address public controller;

    event ControllerUpdated(address indexed newController);
    event Withdrawal(address indexed to, uint256 amount);
    event EmergencyWithdrawal(address indexed to, uint256 amount);

    modifier onlyController() {
        require(msg.sender == controller, "SecurityPool: not controller");
        _;
    }

    constructor(IERC20 _token, address admin, address controller_) Ownable(admin) {
        require(address(_token) != address(0), "SecurityPool: invalid token");
        require(controller_ != address(0), "SecurityPool: invalid controller");
        token = _token;
        controller = controller_;
        emit ControllerUpdated(controller_);
    }

    /**
     * @notice 设置资金池控制者，通常为 BaseToken 合约地址。
     */
    function setController(address _controller) external onlyOwner {
        require(_controller != address(0), "SecurityPool: invalid controller");
        controller = _controller;
        emit ControllerUpdated(_controller);
    }

    /**
     * @notice 由 BaseToken 合约调用，将资金从资金池划转给目标地址。
     */
    function withdraw(address to, uint256 amount)
        external
        onlyController
        whenNotPaused
        nonReentrant
    {
        require(to != address(0), "SecurityPool: invalid recipient");
        require(amount > 0, "SecurityPool: zero amount");
        require(
            token.balanceOf(address(this)) >= amount,
            "SecurityPool: insufficient balance"
        );

        token.transfer(to, amount);
        emit Withdrawal(to, amount);
    }

    /**
     * @notice BaseToken 触发紧急事件时调用，立即暂停池子。
     */
    function controllerPause() external onlyController {
        _pause();
    }

    /**
     * @notice BaseToken 在恢复安全状态后调用，解除暂停。
     */
    function controllerUnpause() external onlyController {
        _unpause();
    }

    /**
     * @notice 所有者在暂停状态下可紧急转移全部资产到指定地址。
     */
    function emergencyWithdrawAll(address to)
        external
        onlyOwner
        whenPaused
        nonReentrant
    {
        require(to != address(0), "SecurityPool: invalid recipient");
        uint256 balance = token.balanceOf(address(this));
        token.transfer(to, balance);
        emit EmergencyWithdrawal(to, balance);
    }
}

