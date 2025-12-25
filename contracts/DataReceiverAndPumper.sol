// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// 导入自定义接口
import { IUniswapV3Router, IUniswapV3Factory } from "./interfaces/IUniswapV3.sol";
import { XZToken } from "./XZToken.sol";

contract DataReceiverAndPumper is Ownable {
    address public tokenAddress;
    address public usdtAddress;
    address public routerAddress;
    uint24 public poolFee;
    
    // 事件
    event DataReceivedAndActed(uint256 actionAmount, bool bought, uint256 amountUsed);

    constructor(
        address _tokenAddress,
        address _usdtAddress,
        address _routerAddress,
        uint24 _poolFee
    ) Ownable(msg.sender) {
        tokenAddress = _tokenAddress;
        usdtAddress = _usdtAddress;
        routerAddress = _routerAddress;
        poolFee = _poolFee;
    }

    // 接收前端解析后的总数据并执行回购销毁
    function receiveDataAndAct(uint256 actionAmount) external onlyOwner {
        require(actionAmount > 0, "Action amount must be positive");
        
        IERC20 usdt = IERC20(usdtAddress);
        uint256 contractBalance = usdt.balanceOf(address(this));

        require(contractBalance >= actionAmount, "Insufficient USDT balance");
        
        // 批准Uniswap路由器花费USDT
        usdt.approve(routerAddress, actionAmount);

        // 使用USDT在Uniswap V3购买token代币
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: usdtAddress,
            tokenOut: tokenAddress,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: actionAmount,
            amountOutMinimum: 0, // 最小输出量（简化版不做复杂检查）
            sqrtPriceLimitX96: 0 // 无价格限制
        });

        uint256 amountOut = IUniswapV3Router(routerAddress).exactInputSingle(params);
        
        // 销毁购买获得的token代币
        XZToken(tokenAddress).burn(amountOut);

        emit DataReceivedAndActed(actionAmount, true, amountOut); // amountOut 是获得并销毁的token量
    }

    // 项目方提取USDT
    function withdrawUSDT(uint256 amount) external onlyOwner {
        IERC20(usdtAddress).transfer(owner(), amount);
    }
    
    // /**
    //  * @dev 获取Uniswap V3池地址
    //  * @return pool 池地址
    //  */
    // function getPoolAddress() public view returns (address pool) {
    //     IUniswapV3Router router = IUniswapV3Router(routerAddress);
    //     address factoryAddress = router.factory();
    //     IUniswapV3Factory factory = IUniswapV3Factory(factoryAddress);
        
    //     address token0 = usdtAddress < tokenAddress ? usdtAddress : tokenAddress;
    //     address token1 = usdtAddress < tokenAddress ? tokenAddress : usdtAddress;
        
    //     return factory.getPool(token0, token1, poolFee);
    // }
}
