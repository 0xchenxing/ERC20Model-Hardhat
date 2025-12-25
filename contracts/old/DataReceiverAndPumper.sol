// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// 导入自定义接口
import { IXZToken } from "../interfaces/IXZToken.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { IUniswapV3Router, IUniswapV3Factory, IUniswapV3Pool } from "../interfaces/IUniswapV3.sol";

contract DataReceiverAndPumper is Ownable, ReentrancyGuard {
    address public XZTokenAddress;
    address public uniswapRouterAddress;
    address public usdtAddress;
    address public poolAddress;
    uint24 public poolFee;
    uint256 public minReserveThresholdXZ;
    uint256 public minReserveThresholdStable;
    
    // Oracle合约地址
    address public oracleAddress;
    
    // Oracle合约接口
    IOracle private oracle;
    
    // 事件
    event OracleSet(address indexed oracleAddress);
    event DataReceivedAndActed(uint256 actionAmount, bool bought, uint256 amountUsed);

    constructor(
        address _XZTokenAddress,
        address _uniswapRouterAddress,
        address _usdtAddress,
        address _poolAddress,
        uint24 _poolFee,
        uint256 _minReserveThresholdXZ,
        uint256 _minReserveThresholdStable,
        address _oracleAddress,
        address initialOwner
    ) Ownable(initialOwner) {
        XZTokenAddress = _XZTokenAddress;
        uniswapRouterAddress = _uniswapRouterAddress;
        usdtAddress = _usdtAddress;
        poolAddress = _poolAddress;
        poolFee = _poolFee;
        minReserveThresholdXZ = _minReserveThresholdXZ;
        minReserveThresholdStable = _minReserveThresholdStable;
        setOracle(_oracleAddress);
    }
    
    // 设置最小储备阈值
    function setMinReserveThresholds(uint256 _minReserveThresholdXZ, uint256 _minReserveThresholdStable) external onlyOwner {
        minReserveThresholdXZ = _minReserveThresholdXZ;
        minReserveThresholdStable = _minReserveThresholdStable;
    }
    
    // 设置Oracle合约地址
    function setOracle(address _oracleAddress) public onlyOwner {
        require(_oracleAddress != address(0), "Oracle address cannot be zero");
        oracleAddress = _oracleAddress;
        oracle = IOracle(_oracleAddress);
        emit OracleSet(_oracleAddress);
    }
    
    // 获取 Uniswap V3 池子信息
    function getPoolReserves() public view returns (uint112 reserveRWA, uint112 reserveStable, uint32 blockTimestampLast) {
        require(poolAddress != address(0), "Pool address not set");
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint128 liquidity = pool.liquidity();
        
        // 确定哪个是 XZ token，哪个是 USDT
        address token0 = pool.token0();
        
        // 计算储备量（简化计算，仅作示例）
        uint256 reserve0;
        uint256 reserve1;
        
        // 使用 sqrtPriceX96 计算储备量
        // 公式：reserve0 = liquidity * (sqrtPriceX96) / 2^96
        //      reserve1 = liquidity / (sqrtPriceX96 / 2^96)
        if (token0 == XZTokenAddress) {
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
    
    // 获取当前价格：返回 1 USDT 可以兑换多少 XZ tokens (考虑精度)
    // XZ token 通常是 18 位小数，USDT 通常是 6 位小数
    function getCurrentPrice() public view returns (uint256 XZAmountPerUSDT) {
        require(poolAddress != address(0), "Pool address not set");
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        
        // 确定价格方向（哪个是token0）
        address token0 = pool.token0();
        bool isXZToken0 = (token0 == XZTokenAddress);
        
        // 计算价格：sqrtPriceX96 表示 sqrt(reserve1 / reserve0) * 2^96
        // 价格 = (sqrtPriceX96^2) / 2^192
        uint256 price;
        if (isXZToken0) {
            // 价格是 USDT/XZ
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) / (1 << 192);
            // 转换为 XZ/USDT
            XZAmountPerUSDT = (1e30) / price; // 使用 1e30 保持精度
        } else {
            // 价格是 XZ/USDT
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) / (1 << 192);
            XZAmountPerUSDT = price;
        }
        
        // 调整精度，使其表示 1 USDT (6 decimals) = XZAmountPerUSDT XZ (18 decimals)
        XZAmountPerUSDT = XZAmountPerUSDT / 1e6;
    }
    
    // 根据 USDT 数量计算等价的 XZ token 数量
    function calculateEquivalentXZAmount(uint256 usdtAmount) public view returns (uint256 XZAmount) {
        uint256 price = getCurrentPrice();
        // usdtAmount 是 6 位小数，price 已经是考虑了精度的值
        // XZAmount = usdtAmount * price / 1e6
        XZAmount = (usdtAmount * price) / 1e6;
    }

    // 键值对结构体
    struct KeyValue {
        bytes key;
        uint256 value;
    }
    
    // Varint 反序列化函数（支持偏移量）
    function decodeVarint(bytes memory data, uint256 offset) public pure returns (uint256 result, uint256 bytesRead) {
        result = 0;
        bytesRead = 0;
        uint256 shift = 0;
        
        for (uint256 i = offset; i < data.length; i++) {
            uint256 byteValue = uint256(uint8(data[i]));
            bytesRead++;
            
            // 获取低7位数据
            uint256 value = byteValue & 0x7F;
            
            // 将数据左移并添加到结果中
            result |= value << shift;
            
            // 检查最高位是否为0，如果是则表示已经到了最后一个字节
            if ((byteValue & 0x80) == 0) {
                break;
            }
            
            // 下一个字节的移位量
            shift += 7;
            
            // 防止溢出
            require(shift < 256, "Varint too long");
        }
        
        return (result, bytesRead);
    }
    
    // 解析Oracle数据函数
    function decodeOracleData(bytes memory data) public pure returns (KeyValue[] memory) {
        require(data.length > 0, "Empty data");
        
        uint256 offset = 0;
        uint256 dataCount;
        uint256 bytesRead;
        
        // 解析数据数量
        (dataCount, bytesRead) = decodeVarint(data, offset);
        offset += bytesRead;
        
        KeyValue[] memory keyValues = new KeyValue[](dataCount);
        
        for (uint256 i = 0; i < dataCount; i++) {
            // 解析键长度
            uint256 keyLength;
            (keyLength, bytesRead) = decodeVarint(data, offset);
            offset += bytesRead;
            
            // 解析键
            bytes memory key = new bytes(keyLength);
            for (uint256 j = 0; j < keyLength; j++) {
                key[j] = data[offset + j];
            }
            offset += keyLength;
            
            // 解析值
            uint256 value;
            (value, bytesRead) = decodeVarint(data, offset);
            offset += bytesRead;
            
            keyValues[i] = KeyValue({
                key: key,
                value: value
            });
        }
        
        return keyValues;
    }

    // 授权的oracle上传链下数据并触发行动
    // pid: 项目ID，用于从Oracle获取数据
    // did: 数据ID，用于从Oracle获取数据
    function receiveDataAndAct(bytes32 pid, bytes32 did) external onlyOwner nonReentrant {
        // 注意：这个函数当前仍然使用onlyOwner修饰符
        // 如果需要让Oracle合约调用，应该修改为：require(msg.sender == oracleAddress, "Only oracle")
        // 但这需要Oracle合约实现相应的调用功能
        // 这里保留onlyOwner以便项目方也可以手动触发
        require(oracleAddress != address(0), "Oracle address not set");
        
        // 1. 从Oracle获取数据
        IOracle.OracleData memory oracleData = oracle.getData(pid, did);
        
        // 2. 检查Oracle数据有效性
        require(oracleData.submitTime > 0, "Oracle data not found");
        
        // 3. 获取项目配置以检查数据TTL
        IOracle.ProjectConfig memory projectConfig = oracle.getProjectConfig(pid);
        require(block.timestamp - oracleData.submitTime <= projectConfig.dataTTL, "Oracle data expired");
        
        // 4. 解析核心数据为键值对数组
        KeyValue[] memory keyValues = decodeOracleData(oracleData.coreData);
        
        // 5. 将所有键对应的值相加作为actionAmount
        uint256 actionAmount = 0;
        for (uint256 i = 0; i < keyValues.length; i++) {
            actionAmount += keyValues[i].value;
        }
        require(actionAmount > 0, "Action amount must be positive");
        
        // 6. 检查储备健康度
        require(checkReserveHealth(), "Pool reserves below threshold");
        
        // 7. 检查价格数据新鲜度（允许最多1小时的数据延迟）
        require(isPriceDataFresh(3600), "Price data too old");
        
        IERC20 usdt = IERC20(usdtAddress);
        uint256 contractBalance = usdt.balanceOf(address(this));

        if (contractBalance >= actionAmount) {
            // 批准Uniswap路由器花费USDT
            usdt.approve(uniswapRouterAddress, actionAmount);

            //8. 授权之后再进行兑换机制检查，确保余额、授权和储备情况均满足要求
            require(checkSwapMechanism(actionAmount), "Swap mechanism not operational");

            // 使用USDT在Uniswap V3购买XZ代币
            IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
                tokenIn: usdtAddress,
                tokenOut: XZTokenAddress,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: actionAmount,
                amountOutMinimum: 0, // 最小输出量（可根据需要调整）
                sqrtPriceLimitX96: 0 // 无价格限制
            });

            uint256 amountOut = IUniswapV3Router(uniswapRouterAddress).exactInputSingle(params);

            emit DataReceivedAndActed(actionAmount, true, amountOut); // amountOut 是获得的XZ量
        } else {
            // 项目方钱包（合约）余额不足，调用销毁战略储备
            // 计算与 USDT 数量价值等同的 XZ token 数量
            uint256 equivalentXZAmount = calculateEquivalentXZAmount(actionAmount);
            require(equivalentXZAmount > 0, "Calculated XZ amount is zero");
            
            // 调用销毁战略储备（价值等同于 actionAmount USDT 的 XZ tokens）
            IXZToken(XZTokenAddress).burnStrategicViaOracle(equivalentXZAmount);

            emit DataReceivedAndActed(actionAmount, false, equivalentXZAmount);
        }
    }

    // 项目方提取USDT（如果需要）
    function withdrawUSDT(uint256 amount) external onlyOwner {
        IERC20(usdtAddress).transfer(owner(), amount);
    }

    // 1. 储备量检查
    function checkReserveHealth() public view returns (bool isHealthy) {
        (uint112 reserveRWA, uint112 reserveStable, ) = getPoolReserves();
        isHealthy = (reserveRWA >= minReserveThresholdXZ && reserveStable >= minReserveThresholdStable);
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
    
    // 查看池的当前健康状况
    function monitorPoolSafety() external {
        (uint112 reserveRWA, uint112 reserveStable, ) = getPoolReserves();
        bool poolHealthy = checkReserveHealth();
        
        emit PoolStatusCheck(msg.sender, poolHealthy);
        
        if (!poolHealthy) {
            emit LowReserveRisk(msg.sender, reserveRWA, reserveStable);
        }
    }
}