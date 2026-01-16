// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISwapRouter02
 * @dev Uniswap V3 ISwapRouter02的接口定义
 */
interface ISwapRouter02 {
    /**
     * @dev ExactInput参数结构体
     */
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    
    /**
     * @dev ExactInputSingle参数结构体
     */
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    /**
     * @dev 多路径精确输入兑换
     * @param params 兑换参数
     * @return amountOut 输出代币数量
     */
    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint256 amountOut);
    
    /**
     * @dev 单路径精确输入兑换
     * @param params 兑换参数
     * @return amountOut 输出代币数量
     */
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
    
    /**
     * @dev 获取Uniswap V3 Factory地址
     * @return factory地址
     */
    function factory() external pure returns (address);
    
    /**
     * @dev 获取WETH9地址
     * @return WETH9地址
     */
    function WETH9() external pure returns (address);
}

/**
 * @title IUniswapV3Factory
 * @dev Uniswap V3 Factory的接口定义
 */
interface IUniswapV3Factory {
    /**
     * @dev 获取Uniswap V3池地址
     * @param tokenA 代币A地址
     * @param tokenB 代币B地址
     * @param fee 费率
     * @return pool 池地址
     */
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/**
 * @title IUniswapV3Pool
 * @dev Uniswap V3 Pool的接口定义
 */
interface IUniswapV3Pool {
    /**
     * @dev 获取池的基本状态
     * @return sqrtPriceX96 当前价格的平方根（X96格式）
     * @return tick 当前价格所在的tick
     * @return observationIndex 当前观察索引
     * @return observationCardinality 当前观察基数
     * @return observationCardinalityNext 下一个观察基数
     * @return feeProtocol 协议费用
     * @return unlocked 是否解锁
     */
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
    
    /**
     * @dev 获取池的流动性
     * @return liquidity 流动性
     */
    function liquidity() external view returns (uint128);
    
    /**
     * @dev 获取池的第一个代币地址
     * @return token0 代币0地址
     */
    function token0() external view returns (address);
    
    /**
     * @dev 获取池的第二个代币地址
     * @return token1 代币1地址
     */
    function token1() external view returns (address);
    
    /**
     * @dev 观察池的历史状态
     * @param secondsAgos 要观察的时间点（相对于当前时间的秒数）
     * @return tickCumulatives 每个时间点的tick累积值
     * @return secondsPerLiquidityCumulativeX128s 每个时间点的秒/流动性累积值（X128格式）
     */
    function observe(uint32[] calldata secondsAgos) external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}