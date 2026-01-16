// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ERC20接口（简化）
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// Uniswap V3 Router接口（精简版）
interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    function exactInputSingle(ExactInputSingleParams calldata params) 
        external 
        payable 
        returns (uint256 amountOut);
}

// 主合约
contract UniswapV3Swapper {
    // Sepolia上的Uniswap V3 Router地址
    address public constant UNISWAP_V3_ROUTER = 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E;
    
    // 常用代币地址（Sepolia测试网）
    address public constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address public constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address public constant DAI = 0x68194a729C2450ad26072b3D33ADaCbcef39D574;
    
    ISwapRouter02 public swapRouter;
    
    // 事件，记录交换结果
    event SwapExecuted(
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    
    constructor() {
        swapRouter = ISwapRouter02(UNISWAP_V3_ROUTER);
    }
    
    /**
     * @dev 使用ETH购买代币（ETH → 代币）
     * @param tokenOut 要购买的目标代币地址
     * @param fee 资金池费率（3000 = 0.3%）
     * @param amountOutMin 可接受的最小输出数量（防止滑点损失）
     */
    function swapETHForToken(
        address tokenOut,
        uint24 fee,
        uint256 amountOutMin
    ) external payable returns (uint256) {
        require(msg.value > 0, "Must send ETH");
        
        // 构建交易参数
        ISwapRouter02.ExactInputSingleParams memory params = 
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: WETH,          // Sepolia上的WETH地址（ETH会自动包装）
                tokenOut: tokenOut,     // 目标代币
                fee: fee,               // 资金池费率（常用：500 = 0.05%）
                recipient: msg.sender,  // 代币发送给调用者
                amountIn: msg.value,    // 输入的ETH数量
                amountOutMinimum: amountOutMin, // 最小输出量
                sqrtPriceLimitX96: 0    // 不限制价格
            });
        
        // 执行交换
        uint256 amountOut = swapRouter.exactInputSingle{value: msg.value}(params);
        
        emit SwapExecuted(
            msg.sender,
            WETH,
            tokenOut,
            msg.value,
            amountOut
        );
        
        return amountOut;
    }
    
    /**
     * @dev 代币之间的交换（代币A → 代币B）
     * @param tokenIn 输入代币地址
     * @param tokenOut 输出代币地址
     * @param fee 资金池费率
     * @param amountIn 输入数量
     * @param amountOutMin 可接受的最小输出数量
     */
    function swapTokenForToken(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256) {
        
        IERC20(tokenIn).approve(UNISWAP_V3_ROUTER, amountIn);
        
        // 构建交易参数
        ISwapRouter02.ExactInputSingleParams memory params = 
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: msg.sender,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });
        
        // 执行交换
        uint256 amountOut = swapRouter.exactInputSingle(params);
        
        emit SwapExecuted(
            msg.sender,
            tokenIn,
            tokenOut,
            amountIn,
            amountOut
        );
        
        return amountOut;
    }
    
    // 接收ETH的回退函数
    receive() external payable {}
}