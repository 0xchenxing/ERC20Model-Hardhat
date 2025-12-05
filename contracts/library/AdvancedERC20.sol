// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AdvancedERC20
 * @dev 增强版ERC20代币，支持独立配置的手续费、裂变关系和销毁功能
 */
abstract contract AdvancedERC20 is ERC20, ERC20Burnable, Ownable {
    // 手续费配置
    uint256 public transferFee; // 转账手续费率 (基点，100 = 1%)
    uint256 public constant FEE_DENOMINATOR = 10000;
    address public feeRecipient;
    mapping(address => bool) public feeExempt; // 免手续费地址
    bool public feeEnabled; // 是否启用转账手续费
    
    // 裂变关系配置
    mapping(address => address) public referrers; // 用户 -> 直接推荐人
    mapping(address => uint256) public referralCount; // 推荐人 -> 直接推荐数量
    uint256 public minReferralTransferAmount; // 设置推荐关系的最低转账金额
    bool public referralEnabled; // 是否启用裂变功能
    
    // 销毁配置
    uint256 private _initialTotalSupply; // 初始总供应量，用于计算已销毁代币数量
    bool public burnEnabled; // 是否启用销毁功能
    
    // 事件
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
    
    /**
     * @dev 构造函数
     * @param name_ 代币名称
     * @param symbol_ 代币符号
     * @param initialSupply_ 初始供应量
     * @param initialTransferFee_ 初始转账手续费率 (基点)
     * @param initialFeeRecipient_ 初始手续费接收地址
     * @param initialOwner 初始合约所有者
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        uint256 initialTransferFee_,
        address initialFeeRecipient_,
        address initialOwner
    ) ERC20(name_, symbol_) Ownable(initialOwner) {
        require(initialTransferFee_ <= 1000, "Fee too high"); // 最大10%手续费
        require(initialFeeRecipient_ != address(0), "Invalid fee recipient");
        
        _mint(initialOwner, initialSupply_);
        _initialTotalSupply = totalSupply(); // 记录初始总供应量
        
        // 初始化手续费配置
        transferFee = initialTransferFee_;
        feeRecipient = initialFeeRecipient_;
        feeExempt[initialOwner] = true;
        feeExempt[initialFeeRecipient_] = true;
        feeEnabled = true; // 默认启用手续费
        
        // 初始化裂变配置
        minReferralTransferAmount = 0; // 默认无最低转账金额限制
        referralEnabled = true;
        
        // 初始化销毁配置
        burnEnabled = true;
    }
    
    /**
     * @dev 重写_update函数，整合所有功能（OpenZeppelin v5.x使用_update代替_transfer）
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        // 1. 首先检查是否是销毁
        if (burnEnabled && to == address(this)) {
            super._update(from, address(0), amount);
            emit TokensBurned(from, amount);
            return;
        }
        
        uint256 finalAmount = amount;
        uint256 feeAmount = 0;
        
        // 2. 处理手续费 - 铸造（from == address(0)）和销毁（to == address(0)）操作不收取手续费
        if (feeEnabled && transferFee > 0 && from != address(0) && to != address(0) && !feeExempt[from]) {
            feeAmount = (amount * transferFee) / FEE_DENOMINATOR;
            if (feeAmount > 0) {
                finalAmount = amount - feeAmount;
            }
        }
        
        // 3. 处理裂变关系 - 只有从非零地址转出到非零地址，且转账金额达到最低要求时才会设置推荐关系
        if (referralEnabled && from != address(0) && to != address(0) && finalAmount > 0 && finalAmount >= minReferralTransferAmount) {
            _handleReferral(from, to);
        }
        
        // 4. 执行实际转账和手续费收取
        // 从发送方扣除总金额（转账金额 + 手续费）
        super._update(from, to, finalAmount);
        if (feeAmount > 0) {
            super._update(from, feeRecipient, feeAmount);
        }
    }
    
    // ========== 手续费功能 ==========
    
    /**
     * @dev 更新转账手续费率
     */
    function setTransferFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high"); // 最大10%
        uint256 oldFee = transferFee;
        transferFee = newFee;
        emit TransferFeeUpdated(oldFee, newFee);
    }
    
    /**
     * @dev 更新手续费接收地址
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }
    
    /**
     * @dev 设置免手续费地址
     */
    function setFeeExempt(address account, bool exempt) external onlyOwner {
        feeExempt[account] = exempt;
        emit FeeExemptUpdated(account, exempt);
    }
    
    /**
     * @dev 启用/禁用转账手续费
     */
    function setFeeEnabled(bool enabled) external onlyOwner {
        feeEnabled = enabled;
        emit FeeEnabledUpdated(enabled);
    }
    
    /**
     * @dev 计算转账手续费
     */
    function calculateTransferFee(uint256 amount) external view returns (uint256) {
        return (amount * transferFee) / FEE_DENOMINATOR;
    }
    
    /**
     * @dev 获取实际转账金额（扣除手续费后）
     */
    function getTransferAmount(uint256 amount) external view returns (uint256) {
        uint256 feeAmount = (amount * transferFee) / FEE_DENOMINATOR;
        return amount - feeAmount;
    }
    
    // ========== 裂变功能 ==========
    
    /**
     * @dev 判断地址是否为合约地址
     * 注意：在构造函数中调用时，合约地址的extcodesize为0
     */
    function _isContract(address account) internal view returns (bool) {
        // 排除零地址
        if (account == address(0)) {
            return false;
        }
        // 检查地址的代码长度
        // 注意：合约在构造过程中extcodesize为0
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(account)
        }
        return codeSize > 0;
    }
    
    /**
     * @dev 处理裂变关系逻辑
     */
    function _handleReferral(address sender, address recipient) internal {
        // 检查推荐系统是否启用
        if (!referralEnabled) {
            return;
        }
        
        // 排除合约地址
        if (_isContract(recipient) || _isContract(sender)) {
            return;
        }
        
        // 防止自推荐
        if (sender == recipient) {
            return;
        }
        
        // 确保所有者转账时不建立推荐关系
        if (sender == owner()) {
            return;
        }
        
        // 如果接收方还没有推荐人，则设置发送方为推荐人
        if (referrers[recipient] == address(0)) {
            referrers[recipient] = sender;
            referralCount[sender]++;
            emit ReferrerSet(recipient, sender);
        }
    }
    
    /**
     * @dev 启用/禁用裂变功能
     */
    function setReferralEnabled(bool enabled) external onlyOwner {
        referralEnabled = enabled;
        emit ReferralEnabledUpdated(enabled);
    }
    
    /**
     * @dev 设置建立推荐关系的最低转账金额
     * @param amount 最低转账金额
     */
    function setMinReferralTransferAmount(uint256 amount) external onlyOwner {
        uint256 oldAmount = minReferralTransferAmount;
        minReferralTransferAmount = amount;
        emit MinReferralTransferAmountUpdated(oldAmount, amount);
    }
    
    /**
     * @dev 获取用户的直接推荐人
     */
    function getReferrer(address user) external view returns (address) {
        return referrers[user];
    }
    
    /**
     * @dev 获取用户的直接推荐数量
     */
    function getReferralCount(address user) external view returns (uint256) {
        return referralCount[user];
    }
    
    /**
     * @dev 检查地址是否在数组中
     * @param arr 地址数组
     * @param addr 要检查的地址
     * @return 如果地址在数组中返回true，否则返回false
     */
    function _isAddressInArray(address[] memory arr, address addr, uint256 count) private pure returns (bool) {
        for (uint256 i = 0; i < count; i++) {
            if (arr[i] == addr) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @dev 获取用户的推荐链，支持指定最大深度，遇到循环会自动停止
     * @param user 要查询的用户地址
     * @param maxDepth 查询的最大深度（0表示不限制深度，返回完整推荐链）
     * @return 推荐链数组，从直接推荐人开始，直到没有推荐人、达到指定深度或遇到循环
     */
    function getReferralChain(address user, uint256 maxDepth) external view returns (address[] memory) {
        // 最大可能的深度，设置一个合理的上限防止gas消耗过大
        uint256 MAX_POSSIBLE_DEPTH = 100;
        
        // 第一次遍历：收集推荐链，遇到循环则停止
        address[] memory tempChain = new address[](MAX_POSSIBLE_DEPTH);
        uint256 actualDepth = 0;
        address currentReferrer = referrers[user];
        
        while (currentReferrer != address(0) && actualDepth < MAX_POSSIBLE_DEPTH) {
            // 检查是否遇到循环
            if (_isAddressInArray(tempChain, currentReferrer, actualDepth)) {
                break;
            }
            
            tempChain[actualDepth] = currentReferrer;
            actualDepth++;
            
            // 检查是否达到指定的最大深度
            if (maxDepth > 0 && actualDepth >= maxDepth) {
                break;
            }
            
            currentReferrer = referrers[currentReferrer];
        }
        
        // 确定返回数组的大小
        uint256 resultDepth = actualDepth;
        if (maxDepth > 0 && maxDepth < actualDepth) {
            resultDepth = maxDepth;
        }
        
        // 创建并填充结果数组
        address[] memory chain = new address[](resultDepth);
        for (uint256 i = 0; i < resultDepth; i++) {
            chain[i] = tempChain[i];
        }
        
        return chain;
    }
    
    /**
     * @dev 获取用户推荐链的实际深度，遇到循环会自动停止
     * @param user 要查询的用户地址
     * @return 推荐链实际深度
     */
    function getReferralDepth(address user) external view returns (uint256) {
        // 最大可能的深度，设置一个合理的上限防止gas消耗过大
        uint256 MAX_POSSIBLE_DEPTH = 100;
        
        address[] memory visited = new address[](MAX_POSSIBLE_DEPTH);
        uint256 depth = 0;
        address currentReferrer = referrers[user];
        
        while (currentReferrer != address(0) && depth < MAX_POSSIBLE_DEPTH) {
            // 检查是否遇到循环
            if (_isAddressInArray(visited, currentReferrer, depth)) {
                break;
            }
            
            visited[depth] = currentReferrer;
            depth++;
            currentReferrer = referrers[currentReferrer];
        }
        
        return depth;
    }
    
    /**
     * @dev 获取指定深度的推荐人，遇到循环会自动停止
     * @param user 要查询的用户地址
     * @param depth 要查询的深度（1表示直接推荐人，2表示推荐人的推荐人，以此类推）
     * @return 该深度的推荐人地址，如果深度超过实际推荐链深度或遇到循环则返回address(0)
     */
    function getReferrerAtDepth(address user, uint256 depth) external view returns (address) {
        require(depth > 0, "Depth must be greater than 0");
        
        // 最大可能的深度，设置一个合理的上限防止gas消耗过大
        uint256 MAX_POSSIBLE_DEPTH = 100;
        
        address[] memory visited = new address[](MAX_POSSIBLE_DEPTH);
        address currentReferrer = referrers[user];
        uint256 currentDepth = 1;
        uint256 visitedCount = 0;
        
        while (currentReferrer != address(0) && currentDepth < depth) {
            // 检查是否遇到循环
            if (_isAddressInArray(visited, currentReferrer, visitedCount)) {
                return address(0);
            }
            
            visited[visitedCount] = currentReferrer;
            visitedCount++;
            
            currentReferrer = referrers[currentReferrer];
            currentDepth++;
            
            // 防止无限循环导致gas消耗过大
            if (visitedCount >= MAX_POSSIBLE_DEPTH) {
                return address(0);
            }
        }
        
        // 检查最终地址是否在循环中
        if (currentReferrer != address(0) && _isAddressInArray(visited, currentReferrer, visitedCount)) {
            return address(0);
        }
        
        return currentDepth == depth ? currentReferrer : address(0);
    }
    
    // ========== 销毁功能 ==========
    
    /**
     * @dev 重写ERC20Burnable的burn函数，添加自定义事件和开关控制
     */
    function burn(uint256 amount) public virtual override {
        require(burnEnabled, "Burn disabled");
        super.burn(amount);
        emit TokensBurned(_msgSender(), amount);
    }
    
    /** 
     * @dev 重写ERC20Burnable的burnFrom函数，添加自定义事件和开关控制
     */
    function burnFrom(address account, uint256 amount) public virtual override {
        require(burnEnabled, "Burn disabled");
        super.burnFrom(account, amount);
        emit TokensBurned(account, amount);
    }
    
    /**
     * @dev 启用/禁用销毁功能
     */
    function setBurnEnabled(bool enabled) external onlyOwner {
        burnEnabled = enabled;
        emit BurnEnabledUpdated(enabled);
    }
    
    /**
     * @dev 获取总销毁量
     */
    function totalBurned() external view returns (uint256) {
        // 防止初始总供应量小于当前总供应量（可能由于额外铸造）
        return _initialTotalSupply >= totalSupply() ? _initialTotalSupply - totalSupply() : 0;
    }
    
    // ========== 配置查询 ==========
    
    /**
     * @dev 获取所有配置信息
     */
    function getConfig() external view returns (
        uint256 currentTransferFee,
        address currentFeeRecipient,
        bool isFeeEnabled,
        bool isReferralEnabled,
        uint256 minReferralTransferAmount_,
        bool isBurnEnabled,
        uint256 totalSupply_,
        uint256 totalBurned_
    ) {
        return (
            transferFee,
            feeRecipient,
            feeEnabled,
            referralEnabled,
            minReferralTransferAmount,
            burnEnabled,
            totalSupply(),
            this.totalBurned()
        );
    }
}