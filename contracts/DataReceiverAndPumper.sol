// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// 导入自定义接口
import { IXZToken } from "./interfaces/IXZToken.sol";
import { IUniswapV3Router, IUniswapV3Factory, IUniswapV3Pool } from "./interfaces/IUniswapV3.sol";



contract DataReceiverAndPumper is Ownable, ReentrancyGuard {
    address public baseTokenAddress;
    address public uniswapRouterAddress;
    address public usdtAddress;
    address public poolAddress;
    uint24 public poolFee;
    uint256 public minReserveThresholdBase;
    uint256 public minReserveThresholdStable;

    // 哈希上链相关
    mapping(bytes32 => uint256) public hashes; // 存储哈希值和对应的时间戳
    event HashStored(bytes32 indexed hash, uint256 timestamp, string indexed dataType);
    event DataReceivedAndActed(uint256 actionAmount, bool bought, uint256 amountUsed);

    constructor(
        address _baseTokenAddress,
        address _uniswapRouterAddress,
        address _usdtAddress,
        address _poolAddress,
        uint24 _poolFee,
        uint256 _minReserveThresholdBase,
        uint256 _minReserveThresholdStable,
        address initialOwner
    ) Ownable(initialOwner) {
        baseTokenAddress = _baseTokenAddress;
        uniswapRouterAddress = _uniswapRouterAddress;
        usdtAddress = _usdtAddress;
        poolAddress = _poolAddress;
        poolFee = _poolFee;
        minReserveThresholdBase = _minReserveThresholdBase;
        minReserveThresholdStable = _minReserveThresholdStable;
    }
    
    // 设置最小储备阈值
    function setMinReserveThresholds(uint256 _minReserveThresholdBase, uint256 _minReserveThresholdStable) external onlyOwner {
        minReserveThresholdBase = _minReserveThresholdBase;
        minReserveThresholdStable = _minReserveThresholdStable;
    }
    
    // 获取 Uniswap V3 池子信息
    function getPoolReserves() public view returns (uint112 reserveRWA, uint112 reserveStable, uint32 blockTimestampLast) {
        require(poolAddress != address(0), "Pool address not set");
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint128 liquidity = pool.liquidity();
        
        // 确定哪个是 BASE token，哪个是 USDT
        address token0 = pool.token0();
        address token1 = pool.token1();
        
        // 计算储备量（简化计算，仅作示例）
        uint256 reserve0;
        uint256 reserve1;
        
        // 使用 sqrtPriceX96 计算储备量
        // 公式：reserve0 = liquidity * (sqrtPriceX96) / 2^96
        //      reserve1 = liquidity / (sqrtPriceX96 / 2^96)
        if (token0 == baseTokenAddress) {
            reserve0 = uint256(liquidity) * uint256(sqrtPriceX96) / (1 << 96);
            reserve1 = uint256(liquidity) * (1 << 96) / uint256(sqrtPriceX96);
            reserveRWA = uint112(reserve0);
            reserveStable = uint112(reserve1);
        } else {
            reserve0 = uint256(liquidity) * (1 << 96) / uint256(sqrtPriceX96);
            reserve1 = uint256(liquidity) * uint256(sqrtPriceX96) / (1 << 96);
            reserveRWA = uint112(reserve1);
            reserveStable = uint112(reserve0);
        }
        
        // V3 池没有直接的 blockTimestampLast，使用当前区块时间
        blockTimestampLast = uint32(block.timestamp);
    }
    
    // 获取当前价格：返回 1 USDT 可以兑换多少 BASE tokens (考虑精度)
    // BASE token 通常是 18 位小数，USDT 通常是 6 位小数
    function getCurrentPrice() public view returns (uint256 baseAmountPerUSDT) {
        require(poolAddress != address(0), "Pool address not set");
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        
        // 确定价格方向（哪个是token0）
        address token0 = pool.token0();
        bool isBaseToken0 = (token0 == baseTokenAddress);
        
        // 计算价格：sqrtPriceX96 表示 sqrt(reserve1 / reserve0) * 2^96
        // 价格 = (sqrtPriceX96^2) / 2^192
        uint256 price;
        if (isBaseToken0) {
            // 价格是 USDT/BASE
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) / (1 << 192);
            // 转换为 BASE/USDT
            baseAmountPerUSDT = (1e30) / price; // 使用 1e30 保持精度
        } else {
            // 价格是 BASE/USDT
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) / (1 << 192);
            baseAmountPerUSDT = price;
        }
        
        // 调整精度，使其表示 1 USDT (6 decimals) = baseAmountPerUSDT BASE (18 decimals)
        baseAmountPerUSDT = baseAmountPerUSDT / 1e6;
    }
    
    // 根据 USDT 数量计算等价的 BASE token 数量
    function calculateEquivalentBaseAmount(uint256 usdtAmount) public view returns (uint256 baseAmount) {
        uint256 price = getCurrentPrice();
        // usdtAmount 是 6 位小数，price 已经是考虑了精度的值
        // baseAmount = usdtAmount * price / 1e6
        baseAmount = (usdtAmount * price) / 1e6;
    }

    // 项目方或授权的oracle上传链下数据并触发行动
    // actionAmount: 用于购买的USDT量（6位小数）
    function receiveDataAndAct(uint256 actionAmount, bytes32 dataHash, string calldata dataType) external onlyOwner nonReentrant {
        require(actionAmount > 0, "Action amount must be positive");
        
        // 1. 检查储备健康度
        require(checkReserveHealth(), "Pool reserves below threshold");
        
        // 2. 检查价格数据新鲜度（允许最多1小时的数据延迟）
        require(isPriceDataFresh(3600), "Price data too old");
        
        // 3. 哈希上链
        storeHash(dataHash, dataType);
        
        IERC20 usdt = IERC20(usdtAddress);
        uint256 contractBalance = usdt.balanceOf(address(this));

        if (contractBalance >= actionAmount) {
            // 批准Uniswap路由器花费USDT
            usdt.approve(uniswapRouterAddress, actionAmount);

            //4. 授权之后再进行兑换机制检查，确保余额、授权和储备情况均满足要求
            require(checkSwapMechanism(actionAmount), "Swap mechanism not operational");

            // 使用USDT在Uniswap V3购买BASE代币
            IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
                tokenIn: usdtAddress,
                tokenOut: baseTokenAddress,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: actionAmount,
                amountOutMinimum: 0, // 最小输出量（可根据需要调整）
                sqrtPriceLimitX96: 0 // 无价格限制
            });

            uint256 amountOut = IUniswapV3Router(uniswapRouterAddress).exactInputSingle(params);

            emit DataReceivedAndActed(actionAmount, true, amountOut); // amountOut 是获得的BASE量
        } else {
            // 项目方钱包（合约）余额不足，调用销毁战略储备
            // 计算与 USDT 数量价值等同的 BASE token 数量
            uint256 equivalentBaseAmount = calculateEquivalentBaseAmount(actionAmount);
            require(equivalentBaseAmount > 0, "Calculated base amount is zero");
            
            // 调用销毁战略储备（价值等同于 actionAmount USDT 的 BASE tokens）
            IXZToken(baseTokenAddress).burnStrategicViaOracle(equivalentBaseAmount);

            emit DataReceivedAndActed(actionAmount, false, equivalentBaseAmount);
        }
    }

    // 通用哈希上链函数
    function storeHash(bytes32 dataHash, string calldata dataType) public onlyOwner {
        require(dataHash != bytes32(0), "Hash cannot be zero");
        require(hashes[dataHash] == 0, "Hash already stored");
        
        hashes[dataHash] = block.timestamp;
        emit HashStored(dataHash, block.timestamp, dataType);
    }

    // 检查哈希是否已上链
    function isHashStored(bytes32 dataHash) external view returns (bool, uint256) {
        uint256 timestamp = hashes[dataHash];
        return (timestamp != 0, timestamp);
    }

    // 项目方提取USDT（如果需要）
    function withdrawUSDT(uint256 amount) external onlyOwner {
        IERC20(usdtAddress).transfer(owner(), amount);
    }

    // 1. 储备量检查
    function checkReserveHealth() public view returns (bool isHealthy) {
        (uint112 reserveRWA, uint112 reserveStable, ) = getPoolReserves();
        isHealthy = (reserveRWA >= minReserveThresholdBase && reserveStable >= minReserveThresholdStable);
    }

    // 2. 兑换机制检查
    function checkSwapMechanism(uint256 amountToSpend) public view returns (bool isOperational) {
        IERC20 usdt = IERC20(usdtAddress);
        uint256 contractUSDTBalance = usdt.balanceOf(address(this));
        uint256 allowance = usdt.allowance(address(this), uniswapRouterAddress);
        
        // 检查合约余额、授权是否充足，以及池子储备健康度
        isOperational = (contractUSDTBalance >= amountToSpend && 
                        allowance >= amountToSpend && 
                        checkReserveHealth());
    }

    // 3. 价格数据有效性检查
    function isPriceDataFresh(uint32 maxDataAge) public view returns (bool isFresh) {
        (, , uint32 timestamp) = getPoolReserves();
        // 检查Uniswap储备量数据的新旧程度
        isFresh = (block.timestamp - timestamp) <= maxDataAge;
        // 注意：这里检查的是Uniswap池子数据年龄。如果你使用外部预言机，需要调用其特定方法。
    }

    // 4. 安全状态监控与事件
    event LowReserveRisk(address indexed pool, uint256 reserveRWA, uint256 reserveStable);
    event PoolStatusCheck(address indexed pool, bool healthy);
    
    function monitorPoolSafety() external {
        (uint112 reserveRWA, uint112 reserveStable, ) = getPoolReserves();
        bool poolHealthy = checkReserveHealth();
        
        emit PoolStatusCheck(msg.sender, poolHealthy);
        
        if (!poolHealthy) {
            emit LowReserveRisk(msg.sender, reserveRWA, reserveStable);
        }
    }
}