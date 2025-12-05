import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const privateKey = process.env.PRIVATE_KEY || "";
const alchemyProjectId = process.env.ALCHEMY_PROJECT_ID || "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks: {
    // Hardhat本地网络（默认）
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    
    // 本地测试网络（如Ganache）
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    
    // Ethereum Sepolia测试网
    // sepolia: {
    //   url: `https://eth-sepolia.g.alchemy.com/v2/${alchemyProjectId}`,
    //   accounts: [privateKey]
    // },
    
    // // Ethereum主网
    // mainnet: {
    //   url: "https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID",
    //   accounts: ["YOUR_PRIVATE_KEY"]
    // },
    
    // // Polygon Mumbai测试网
    // mumbai: {
    //   url: "https://rpc-mumbai.maticvigil.com",
    //   accounts: ["YOUR_PRIVATE_KEY"]
    // },
    
    // // Polygon主网
    // polygon: {
    //   url: "https://polygon-rpc.com/",
    //   accounts: ["YOUR_PRIVATE_KEY"]
    // },
    
    // // BSC测试网
    // bscTestnet: {
    //   url: "https://data-seed-prebsc-1-s1.binance.org:8545",
    //   accounts: ["YOUR_PRIVATE_KEY"]
    // },
    
    // // BSC主网
    // bsc: {
    //   url: "https://bsc-dataseed.binance.org/",
    //   accounts: ["YOUR_PRIVATE_KEY"]
    // }
  },
  // etherscan: {
  //   // 用于验证合约的API密钥
  //   apiKey: "YOUR_ETHERSCAN_API_KEY"
  // }
};

export default config;
