import { ethers } from "hardhat";

async function main() {
  // 获取部署者账户
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // 获取Oracle合约工厂
  const OracleFactory = await ethers.getContractFactory("Oracle");

  // 部署Oracle合约，将部署者设置为初始所有者
  const oracle = await OracleFactory.deploy(deployer.address);

  // 等待合约部署完成
  await oracle.waitForDeployment();

  // 获取合约地址
  const oracleAddress = await oracle.getAddress();
  console.log("Oracle contract deployed to:", oracleAddress);

  // 验证合约（可选，需要配置BSCScan API密钥）
  // await hre.run("verify:verify", {
  //   address: oracleAddress,
  //   constructorArguments: [deployer.address],
  // });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
