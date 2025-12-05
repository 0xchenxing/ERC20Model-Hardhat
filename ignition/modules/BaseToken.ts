import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// 替换为实际的项目所有者地址
const PROJECT_OWNER = "0x9D8D19d8f69e470a51b9A8f7e6d2A4522cFB0B70";

const BaseTokenModule = buildModule("BaseTokenModule", (m) => {
  // 获取部署者地址作为项目所有者
  const projectOwner = m.getAccount(0);
  
  // 部署BaseToken合约
  const baseToken = m.contract("BaseToken", [projectOwner]);

  return { baseToken };
});

export default BaseTokenModule;