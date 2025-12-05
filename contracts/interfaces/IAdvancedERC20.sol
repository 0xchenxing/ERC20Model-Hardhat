// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAdvancedERC20
 * @dev AdvancedERC20代币合约接口定义
 */
interface IAdvancedERC20 {
    // 公共状态变量的getter函数（Solidity自动生成）
    function transferFee() external view returns (uint256);
    function FEE_DENOMINATOR() external view returns (uint256);
    function feeRecipient() external view returns (address);
    function feeExempt(address) external view returns (bool);
    function feeEnabled() external view returns (bool);
    function referrers(address) external view returns (address);
    function referralCount(address) external view returns (uint256);
    function minReferralTransferAmount() external view returns (uint256);
    function referralEnabled() external view returns (bool);
    function burnEnabled() external view returns (bool);

    // 事件声明
    event TransferFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event FeeExemptUpdated(address account, bool isExempt);
    event FeeEnabledUpdated(bool enabled);
    event ReferrerSet(address indexed user, address indexed referrer);
    event ReferralEnabledUpdated(bool enabled);
    event TokensBurned(address indexed burner, uint256 amount);
    event BurnEnabledUpdated(bool enabled);
    event MinReferralTransferAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event TokensBurnedViaTransfer(address indexed from, uint256 amount);

    // 手续费功能相关函数
    function setTransferFee(uint256 newFee) external;
    function setFeeRecipient(address newRecipient) external;
    function setFeeExempt(address account, bool exempt) external;
    function setFeeEnabled(bool enabled) external;
    function calculateTransferFee(uint256 amount) external view returns (uint256);
    function getTransferAmount(uint256 amount) external view returns (uint256);

    // 裂变功能相关函数
    function setReferralEnabled(bool enabled) external;
    function setMinReferralTransferAmount(uint256 amount) external;
    function getReferrer(address user) external view returns (address);
    function getReferralCount(address user) external view returns (uint256);
    function getReferralChain(address user, uint256 maxDepth) external view returns (address[] memory);
    function getReferralDepth(address user) external view returns (uint256);
    function getReferrerAtDepth(address user, uint256 depth) external view returns (address);

    // 销毁功能相关函数
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function setBurnEnabled(bool enabled) external;
    function totalBurned() external view returns (uint256);

    // 配置查询函数
    function getConfig() external view returns (
        uint256 currentTransferFee,
        address currentFeeRecipient,
        bool isFeeEnabled,
        bool isReferralEnabled,
        uint256 minReferralTransferAmount_,
        bool isBurnEnabled,
        uint256 totalSupply_,
        uint256 totalBurned_
    );
}