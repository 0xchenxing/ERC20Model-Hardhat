import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Sepolia 网络配置参数
// 这些参数需要根据实际情况配置，可以通过环境变量设置
const SEPOLIA_CONFIG = {
  // Uniswap V2 Router 地址 (Sepolia 测试网)
  // 注意：Sepolia 可能没有标准的 Uniswap，需要替换为实际的 DEX 地址
  // 如果使用其他 DEX，请替换为对应的 Router 地址
  UNISWAP_ROUTER: process.env.SEPOLIA_UNISWAP_ROUTER || "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  
  // USDT 地址 (Sepolia 测试网)
  // 如果没有 USDT，可以使用其他稳定币或测试代币地址
  USDT_ADDRESS: process.env.SEPOLIA_USDT_ADDRESS || "0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0",
  
  // Uniswap Pair 地址 (BASE/USDT)
  // 重要：需要在实际部署前创建流动性池并获取 pair 地址
  // 如果还没有创建池子，可以先使用零地址，部署后再通过 setPairAddress 设置
  PAIR_ADDRESS: process.env.SEPOLIA_PAIR_ADDRESS || "0x0000000000000000000000000000000000000000",
  
  // 最小储备阈值 (BASE token, 18位小数)
  // 默认: 1000 tokens = 1000000000000000000000
  MIN_RESERVE_THRESHOLD_BASE: process.env.MIN_RESERVE_THRESHOLD_BASE || "1000000000000000000000",
  
  // 最小储备阈值 (USDT, 6位小数)
  // 默认: 1 USDT = 1000000
  MIN_RESERVE_THRESHOLD_STABLE: process.env.MIN_RESERVE_THRESHOLD_STABLE || "1000000",
};

const SepoliaDeploymentModule = buildModule("SepoliaDeploymentModule", (m) => {
  // 获取部署者地址作为项目所有者
  const projectOwner = m.getAccount(0);
  
  // 1. 部署 BaseToken 合约
  // 构造函数参数: projectOwner (地址)
  const baseToken = m.contract("BaseToken", [projectOwner]);
  
  // 2. 部署 DataReceiverAndPumper 合约
  // 注意：baseToken 合约引用会自动转换为地址
  const dataReceiverAndPumper = m.contract("DataReceiverAndPumper", [
    baseToken, // baseTokenAddress - 自动从合约引用获取地址
    SEPOLIA_CONFIG.UNISWAP_ROUTER, // uniswapRouterAddress
    SEPOLIA_CONFIG.USDT_ADDRESS, // usdtAddress
    SEPOLIA_CONFIG.PAIR_ADDRESS, // pairAddress
    SEPOLIA_CONFIG.MIN_RESERVE_THRESHOLD_BASE, // minReserveThresholdBase (uint256)
    SEPOLIA_CONFIG.MIN_RESERVE_THRESHOLD_STABLE, // minReserveThresholdStable (uint256)
    projectOwner, // initialOwner
  ]);

  return { 
    baseToken,
    dataReceiverAndPumper 
  };
});

export default SepoliaDeploymentModule;

