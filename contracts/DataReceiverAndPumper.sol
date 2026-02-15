// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// 导入自定义接口
import { ISwapRouter02, IUniswapV3Factory } from "./interfaces/IUniswapV3.sol";
import { XZToken } from "./XZToken.sol";

contract DataReceiverAndPumper {
    address public constant token = 0xf88789848F2115aC6Cc373113d02dc00e08DC954;//此为sepolia测试网的token地址
    address public constant usdt = 0x2Bd4D30d4E026146039600aF11e83e4f8277BbDD;//此为sepolia测试网的USDT地址
    address public constant router = 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E;//此为sepolia测试网的UniswapV3 ISwapRouter02地址
    uint24 public constant poolFee = 3000;
    
    // 事件
    event DataReceivedAndActed(uint256 actionAmount, bool bought, uint256 amountUsed);

    constructor() {}

    // 接收前端解析后的总数据并执行回购销毁
    function receiveDataAndAct(uint256 actionAmount) external {
        require(actionAmount > 0, "Action amount must be positive");
        
        IERC20 USDT = IERC20(usdt);
        
        //提前授权USDT给合约
        USDT.transferFrom(msg.sender, address(this), actionAmount);
        // 批准Uniswap路由器花费USDT
        USDT.approve(router, actionAmount);

        // 使用USDT在Uniswap V3购买token代币
        ISwapRouter02.ExactInputSingleParams memory params = ISwapRouter02.ExactInputSingleParams({
            tokenIn: usdt,
            tokenOut: token,
            fee: poolFee,
            recipient: address(this),
            amountIn: actionAmount,
            amountOutMinimum: 0, // 最小输出量（简化版不做复杂检查）
            sqrtPriceLimitX96: 0 // 无价格限制
        });

        uint256 amountOut = ISwapRouter02(router).exactInputSingle(params);
        
        // 销毁购买获得的token代币
        XZToken(token).burn(amountOut);

        emit DataReceivedAndActed(actionAmount, true, amountOut); // amountOut 是获得并销毁的token量
    }
    
    /**
     * @dev 获取Uniswap V3池地址
     * @return pool 池地址
     */
    function getPoolAddress() public view returns (address pool) {
        ISwapRouter02 router = ISwapRouter02(router);
        address factoryAddress = router.factory();
        IUniswapV3Factory factory = IUniswapV3Factory(factoryAddress);
        
        return factory.getPool(usdt, token, poolFee);
    }
}
