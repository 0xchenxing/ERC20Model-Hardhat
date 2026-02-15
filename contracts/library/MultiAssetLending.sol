// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IUniswapV3.sol";

/**
 * @title 多资产质押借贷合约
 * @dev 支持多种ERC20抵押品，借贷USDT和USDC，使用Uniswap V3获取价格
 */
contract MultiAssetLending is Ownable {
    // ============ 结构体定义 ============
    
    struct ReserveData {
        uint256 totalLiquidity;      // 总流动性
        uint256 totalBorrowed;       // 总借款
        uint256 borrowRate;          // 借款利率（年化，1e18=100%）
        uint256 utilizationRate;     // 资金利用率
        bool isActive;               // 是否激活
    }
    
    struct UserPosition {
        mapping(address => uint256) collateralBalances;  // 抵押品余额
        mapping(address => uint256) borrowBalances;      // 借款余额
        uint256 lastUpdateTime;                          // 最后更新时间
    }
    
    struct CollateralConfig {
        bool isEnabled;             // 是否启用为抵押品
        uint256 collateralFactor;   // 抵押因子（7500 = 75%）
        uint256 liquidationFactor;  // 清算因子（8000 = 80%）
        uint256 liquidationPenalty; // 清算罚金（11000 = 10%）
        address oraclePool;         // Uniswap V3池地址（对USDC）
        uint256 oracleDecimals;     // 预言机精度
    }
    
    // ============ 状态变量 ============
    
    // 支持的借贷代币（稳定币）
    address[] public borrowTokens;
    
    // 支持的抵押代币
    address[] public collateralTokens;
    
    // 数据存储
    mapping(address => ReserveData) public reserves;
    mapping(address => UserPosition) private _positions;
    mapping(address => CollateralConfig) public collateralConfigs;
    
    // 利率模型参数
    uint256 public constant BASE_RATE = 50000000000000000; // 5% 基础利率
    uint256 public constant RATE_SLOPE_1 = 100000000000000000; // 10% 第一斜率
    uint256 public constant RATE_SLOPE_2 = 300000000000000000; // 30% 第二斜率
    uint256 public constant OPTIMAL_UTILIZATION = 8000; // 80% 最优利用率
    
    // 时间参数（秒）
    uint256 public constant SECONDS_PER_YEAR = 31536000;
    
    // 事件
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount);
    event Repay(address indexed user, address indexed token, uint256 amount);
    event Liquidate(
        address indexed liquidator,
        address indexed user,
        address collateralToken,
        address borrowToken,
        uint256 collateralSeized,
        uint256 debtRepaid
    );
    event CollateralConfigured(address indexed token, CollateralConfig config);
    
    // ============ 构造函数 ============
    
    constructor(address initialOwner, address usdtAddress, address usdcAddress) Ownable(initialOwner) {
        // 初始化借贷代币
        require(usdtAddress != address(0), "USDT address cannot be zero");
        require(usdcAddress != address(0), "USDC address cannot be zero");
        
        borrowTokens.push(usdtAddress); // USDT
        borrowTokens.push(usdcAddress); // USDC
    }
    
    // ============ 权限函数 ============
    
    /**
     * @dev 配置抵押品参数
     */
    function configureCollateral(
        address token,
        bool isEnabled,
        uint256 collateralFactor,   // 7500 = 75%
        uint256 liquidationFactor,  // 8000 = 80%
        uint256 liquidationPenalty, // 11000 = 10%
        address oraclePool
    ) external onlyOwner {
        require(collateralFactor < liquidationFactor, "Invalid factors");
        require(liquidationPenalty >= 10000, "Invalid penalty");
        
        // 检查是否已存在
        bool exists = false;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            if (collateralTokens[i] == token) {
                exists = true;
                break;
            }
        }
        
        if (!exists) {
            collateralTokens.push(token);
        }
        
        collateralConfigs[token] = CollateralConfig({
            isEnabled: isEnabled,
            collateralFactor: collateralFactor,
            liquidationFactor: liquidationFactor,
            liquidationPenalty: liquidationPenalty,
            oraclePool: oraclePool,
            oracleDecimals: 18 // 默认精度，可根据实际情况调整
        });
        
        emit CollateralConfigured(token, collateralConfigs[token]);
    }
    
    /**
     * @dev 激活/停用借贷池
     */
    function setReserveActive(address token, bool active) external onlyOwner {
        reserves[token].isActive = active;
    }
    
    // ============ 用户操作函数 ============
    
    /**
     * @dev 存入抵押品
     */
    function deposit(address token, uint256 amount) external {
        CollateralConfig storage config = collateralConfigs[token];
        require(config.isEnabled, "Token not enabled as collateral");
        
        // 转移代币
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        // 更新用户仓位
        UserPosition storage position = _positions[msg.sender];
        position.collateralBalances[token] += amount;
        position.lastUpdateTime = block.timestamp;
        
        emit Deposit(msg.sender, token, amount);
    }
    
    /**
     * @dev 提取抵押品
     */
    function withdraw(address token, uint256 amount) external {
        UserPosition storage position = _positions[msg.sender];
        require(position.collateralBalances[token] >= amount, "Insufficient collateral");
        
        // 检查健康因子
        uint256 healthFactor = _calculateHealthFactor(msg.sender);
        require(healthFactor >= 1e18, "Health factor too low");
        
        // 更新仓位
        position.collateralBalances[token] -= amount;
        position.lastUpdateTime = block.timestamp;
        
        // 返还代币
        require(
            IERC20(token).transfer(msg.sender, amount),
            "Transfer failed"
        );
        
        emit Withdraw(msg.sender, token, amount);
    }
    
    /**
     * @dev 借款
     */
    function borrow(address token, uint256 amount) external {
        // 检查是否为支持的借贷代币
        bool isBorrowToken = false;
        for (uint256 i = 0; i < borrowTokens.length; i++) {
            if (borrowTokens[i] == token) {
                isBorrowToken = true;
                break;
            }
        }
        require(isBorrowToken, "Token not supported for borrowing");
        require(reserves[token].isActive, "Reserve not active");
        
        // 检查流动性
        uint256 availableLiquidity = _getAvailableLiquidity(token);
        require(availableLiquidity >= amount, "Insufficient liquidity");
        
        // 临时增加债务以计算健康因子
        UserPosition storage position = _positions[msg.sender];
        uint256 oldDebt = position.borrowBalances[token];
        position.borrowBalances[token] += amount;
        
        // 计算健康因子
        uint256 healthFactor = _calculateHealthFactor(msg.sender);
        require(healthFactor >= 1e18, "Health factor too low");
        
        // 更新储备池
        reserves[token].totalBorrowed += amount;
        _updateReserveRates(token);
        
        // 转移代币给用户
        require(
            IERC20(token).transfer(msg.sender, amount),
            "Transfer failed"
        );
        
        emit Borrow(msg.sender, token, amount);
    }
    
    /**
     * @dev 还款
     */
    function repay(address token, uint256 amount) external {
        UserPosition storage position = _positions[msg.sender];
        require(position.borrowBalances[token] >= amount, "Repay amount exceeds debt");
        
        // 转移代币
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        // 更新仓位
        position.borrowBalances[token] -= amount;
        position.lastUpdateTime = block.timestamp;
        
        // 更新储备池
        reserves[token].totalBorrowed -= amount;
        _updateReserveRates(token);
        
        emit Repay(msg.sender, token, amount);
    }
    
    /**
     * @dev 清算不合格仓位
     */
    function liquidate(
        address user,
        address collateralToken,
        address borrowToken,
        uint256 debtToCover
    ) external {
        // 检查健康因子
        uint256 healthFactor = _calculateHealthFactor(user);
        require(healthFactor < 1e18, "Position not liquidatable");
        
        UserPosition storage position = _positions[user];
        require(position.borrowBalances[borrowToken] >= debtToCover, "Debt too high");
        
        CollateralConfig storage config = collateralConfigs[collateralToken];
        require(config.isEnabled, "Collateral not enabled");
        
        // 计算抵押品价值
        uint256 collateralPrice = _getPrice(collateralToken);
        uint256 collateralDecimals = 10 ** IERC20Metadata(collateralToken).decimals();
        uint256 borrowDecimals = 10 ** IERC20Metadata(borrowToken).decimals();
        
        // 计算需要没收的抵押品数量
        uint256 collateralValueToSeize = (debtToCover * config.liquidationPenalty) / 10000;
        uint256 collateralToSeize = (collateralValueToSeize * borrowDecimals) / collateralPrice;
        collateralToSeize = (collateralToSeize * 1e18) / collateralDecimals;
        
        require(
            position.collateralBalances[collateralToken] >= collateralToSeize,
            "Insufficient collateral"
        );
        
        // 转移债务
        require(
            IERC20(borrowToken).transferFrom(msg.sender, address(this), debtToCover),
            "Transfer failed"
        );
        
        // 更新被清算用户的仓位
        position.borrowBalances[borrowToken] -= debtToCover;
        position.collateralBalances[collateralToken] -= collateralToSeize;
        
        // 更新储备池
        reserves[borrowToken].totalBorrowed -= debtToCover;
        _updateReserveRates(borrowToken);
        
        // 给清算人抵押品
        require(
            IERC20(collateralToken).transfer(msg.sender, collateralToSeize),
            "Transfer failed"
        );
        
        emit Liquidate(
            msg.sender,
            user,
            collateralToken,
            borrowToken,
            collateralToSeize,
            debtToCover
        );
    }
    
    // ============ 视图函数 ============
    
    /**
     * @dev 获取用户健康因子
     */
    function getHealthFactor(address user) external view returns (uint256) {
        return _calculateHealthFactor(user);
    }
    
    /**
     * @dev 获取用户仓位信息
     */
    function getUserPosition(
        address user,
        address collateralToken,
        address borrowToken
    ) external view returns (uint256 collateralBalance, uint256 borrowBalance) {
        UserPosition storage position = _positions[user];
        return (
            position.collateralBalances[collateralToken],
            position.borrowBalances[borrowToken]
        );
    }
    
    /**
     * @dev 获取可用流动性
     */
    function getAvailableLiquidity(address token) external view returns (uint256) {
        return _getAvailableLiquidity(token);
    }
    
    /**
     * @dev 计算借款利息
     */
    function calculateBorrowInterest(
        address user,
        address token
    ) external view returns (uint256) {
        UserPosition storage position = _positions[user];
        uint256 debt = position.borrowBalances[token];
        if (debt == 0) return 0;
        
        uint256 timeElapsed = block.timestamp - position.lastUpdateTime;
        uint256 borrowRate = reserves[token].borrowRate;
        
        return (debt * borrowRate * timeElapsed) / (SECONDS_PER_YEAR * 1e18);
    }
    
    // ============ 内部函数 ============
    
    /**
     * @dev 从Uniswap V3获取价格（使用TWAP）
     */
    function _getPrice(address token) internal view returns (uint256) {
        CollateralConfig storage config = collateralConfigs[token];
        require(config.oraclePool != address(0), "Oracle not configured");
        
        IUniswapV3Pool pool = IUniswapV3Pool(config.oraclePool);
        
        // 使用TWAP获取价格（取最近1小时的平均值）
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 3600; // 1小时前
        secondsAgos[1] = 0;     // 当前
        
        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
        
        // 计算时间加权平均tick
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 timeWeightedAverageTick = int24(tickCumulativesDelta / int56(3600));
        
        // 防止极端情况
        if (timeWeightedAverageTick < pool.minTick()) {
            timeWeightedAverageTick = pool.minTick();
        } else if (timeWeightedAverageTick > pool.maxTick()) {
            timeWeightedAverageTick = pool.maxTick();
        }
        
        // 将tick转换为价格
        uint256 price = _tickToPrice(timeWeightedAverageTick);
        
        // 调整精度
        uint256 tokenDecimals = IERC20Metadata(token).decimals();
        uint256 usdcDecimals = 6; // USDC有6位小数
        
        if (tokenDecimals > usdcDecimals) {
            price = price / (10 ** (tokenDecimals - usdcDecimals));
        } else {
            price = price * (10 ** (usdcDecimals - tokenDecimals));
        }
        
        return price;
    }
    
    /**
     * @dev 将tick转换为价格
     */
    function _tickToPrice(int24 tick) internal pure returns (uint256) {
        // 简化的tick到价格转换
        // 实际实现应该使用更精确的数学计算
        uint256 price = 1e18; // 基础价格
        int24 absTick = tick < 0 ? -tick : tick;
        
        for (int24 i = 0; i < absTick; i++) {
            if (tick > 0) {
                price = price * 10001 / 10000; // 每个tick上涨约0.01%
            } else {
                price = price * 10000 / 10001; // 每个tick下跌约0.01%
            }
        }
        
        return price;
    }
    
    /**
     * @dev 计算健康因子
     */
    function _calculateHealthFactor(address user) internal view returns (uint256) {
        UserPosition storage position = _positions[user];
        
        uint256 totalCollateralValue = 0;
        uint256 totalBorrowValue = 0;
        
        // 计算总抵押价值
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 balance = position.collateralBalances[token];
            
            if (balance > 0 && collateralConfigs[token].isEnabled) {
                uint256 price = _getPrice(token);
                uint256 tokenDecimals = 10 ** IERC20Metadata(token).decimals();
                uint256 collateralValue = (balance * price) / tokenDecimals;
                totalCollateralValue += collateralValue;
            }
        }
        
        // 计算总借款价值（假设稳定币1:1美元）
        for (uint256 i = 0; i < borrowTokens.length; i++) {
            address token = borrowTokens[i];
            uint256 debt = position.borrowBalances[token];
            if (debt > 0) {
                totalBorrowValue += debt;
            }
        }
        
        if (totalBorrowValue == 0) return type(uint256).max;
        
        // 计算加权抵押价值
        uint256 weightedCollateralValue = 0;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 balance = position.collateralBalances[token];
            
            if (balance > 0 && collateralConfigs[token].isEnabled) {
                uint256 price = _getPrice(token);
                uint256 tokenDecimals = 10 ** IERC20Metadata(token).decimals();
                uint256 collateralValue = (balance * price) / tokenDecimals;
                uint256 collateralFactor = collateralConfigs[token].collateralFactor;
                weightedCollateralValue += (collateralValue * collateralFactor) / 10000;
            }
        }
        
        return (weightedCollateralValue * 1e18) / totalBorrowValue;
    }
    
    /**
     * @dev 获取可用流动性
     */
    function _getAvailableLiquidity(address token) internal view returns (uint256) {
        uint256 contractBalance = IERC20(token).balanceOf(address(this));
        uint256 totalBorrowed = reserves[token].totalBorrowed;
        
        if (contractBalance > totalBorrowed) {
            return contractBalance - totalBorrowed;
        }
        return 0;
    }
    
    /**
     * @dev 更新储备池利率
     */
    function _updateReserveRates(address token) internal {
        ReserveData storage reserve = reserves[token];
        
        uint256 totalLiquidity = IERC20(token).balanceOf(address(this));
        if (totalLiquidity == 0) {
            reserve.borrowRate = BASE_RATE;
            reserve.utilizationRate = 0;
            return;
        }
        
        // 计算资金利用率
        reserve.utilizationRate = (reserve.totalBorrowed * 10000) / totalLiquidity;
        
        // 根据利用率计算利率
        if (reserve.utilizationRate <= OPTIMAL_UTILIZATION) {
            reserve.borrowRate = BASE_RATE + 
                (reserve.utilizationRate * RATE_SLOPE_1) / OPTIMAL_UTILIZATION;
        } else {
            uint256 excessUtilization = reserve.utilizationRate - OPTIMAL_UTILIZATION;
            reserve.borrowRate = BASE_RATE + RATE_SLOPE_1 +
                (excessUtilization * RATE_SLOPE_2) / (10000 - OPTIMAL_UTILIZATION);
        }
    }
    
    /**
     * @dev 紧急提取代币（仅Owner）
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(owner(), amount), "Transfer failed");
    }
}