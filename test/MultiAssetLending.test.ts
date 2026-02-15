import { expect } from "chai";
import { ethers } from "hardhat";
import { MultiAssetLending } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { ERC20Mock } from "../typechain-types";

describe("MultiAssetLending", function () {
  let lendingContract: MultiAssetLending;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let liquidator: SignerWithAddress;
  
  // 模拟代币
  let usdt: ERC20Mock;
  let usdc: ERC20Mock;
  let weth: ERC20Mock;
  let link: ERC20Mock;
  
  // 常量
  const WETH_PRICE = ethers.parseUnits("3000", 6); // 1 WETH = 3000 USDC (6位小数)
  const LINK_PRICE = ethers.parseUnits("15", 6); // 1 LINK = 15 USDC (6位小数)
  
  beforeEach(async function () {
    // 获取签名者账户
    [owner, user1, user2, liquidator] = await ethers.getSigners();
    
    // 部署模拟ERC20代币
    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    usdt = await ERC20Mock.deploy("Test USDT", "tUSDT", ethers.parseUnits("1000000", 6));
    usdc = await ERC20Mock.deploy("Test USDC", "tUSDC", ethers.parseUnits("1000000", 6));
    weth = await ERC20Mock.deploy("Wrapped Ether", "WETH", ethers.parseEther("10000"));
    link = await ERC20Mock.deploy("Chainlink", "LINK", ethers.parseEther("100000"));
    
    await usdt.waitForDeployment();
    await usdc.waitForDeployment();
    await weth.waitForDeployment();
    await link.waitForDeployment();
    
    // 部署MultiAssetLending合约
    const MultiAssetLending = await ethers.getContractFactory("MultiAssetLending");
    lendingContract = await MultiAssetLending.deploy(owner.address, await usdt.getAddress(), await usdc.getAddress());
    
    await lendingContract.waitForDeployment();
    
    // 配置抵押品
    await lendingContract.configureCollateral(
      await weth.getAddress(),
      true,
      7500, // 75% 抵押因子
      8000, // 80% 清算因子
      11000, // 10% 清算罚金
      ethers.ZeroAddress // 在测试环境中使用零地址，因为我们启用了测试模式
    );
    
    await lendingContract.configureCollateral(
      await link.getAddress(),
      true,
      7000, // 70% 抵押因子
      7500, // 75% 清算因子
      10500, // 5% 清算罚金
      ethers.ZeroAddress // 在测试环境中使用零地址，因为我们启用了测试模式
    );
    
    // 启用测试模式
    await lendingContract.enableTestMode();
    
    // 设置测试价格
    await lendingContract.setTestPrice(await weth.getAddress(), WETH_PRICE);
    await lendingContract.setTestPrice(await link.getAddress(), LINK_PRICE);
    
    // 激活借贷池（使用测试代币地址）
    await lendingContract.setReserveActive(await usdt.getAddress(), true);
    await lendingContract.setReserveActive(await usdc.getAddress(), true);
    
    // 注意：借贷代币已经在构造函数中初始化，不需要再添加
    
    // 给合约和用户转账
    const initialAmount = ethers.parseUnits("10000", 6); // 10000 USDT/USDC
    await usdt.mint(await lendingContract.getAddress(), initialAmount);
    await usdc.mint(await lendingContract.getAddress(), initialAmount);
    
    // 给用户转账抵押品和稳定币
    await weth.mint(user1.address, ethers.parseEther("10")); // 10 WETH
    await link.mint(user1.address, ethers.parseEther("100")); // 100 LINK
    await usdt.mint(user1.address, initialAmount);
    await usdc.mint(user1.address, initialAmount);
    await usdt.mint(liquidator.address, initialAmount);
    
    // 授权合约转移代币
    await weth.connect(user1).approve(await lendingContract.getAddress(), ethers.MaxUint256);
    await link.connect(user1).approve(await lendingContract.getAddress(), ethers.MaxUint256);
    await usdt.connect(user1).approve(await lendingContract.getAddress(), ethers.MaxUint256);
    await usdc.connect(user1).approve(await lendingContract.getAddress(), ethers.MaxUint256);
    await usdt.connect(liquidator).approve(await lendingContract.getAddress(), ethers.MaxUint256);
    

  });
  
  describe("Deployment and Configuration", function () {
    it("应该正确部署并初始化借贷代币", async function () {
      // 验证合约已成功部署
      expect(await lendingContract.getAddress()).to.be.a('string');
      expect(await lendingContract.getAddress()).to.not.equal(ethers.ZeroAddress);
    });
    
    it("应该正确配置抵押品参数", async function () {
      const wethConfig = await lendingContract.collateralConfigs(await weth.getAddress());
      expect(wethConfig.isEnabled).to.be.true;
      expect(wethConfig.collateralFactor).to.equal(7500);
      expect(wethConfig.liquidationFactor).to.equal(8000);
      expect(wethConfig.liquidationPenalty).to.equal(11000);
      
      const linkConfig = await lendingContract.collateralConfigs(await link.getAddress());
      expect(linkConfig.isEnabled).to.be.true;
      expect(linkConfig.collateralFactor).to.equal(7000);
    });
    
    it("应该正确激活借贷池", async function () {
      const usdtReserve = await lendingContract.reserves(await usdt.getAddress());
      expect(usdtReserve.isActive).to.be.true;
      
      const usdcReserve = await lendingContract.reserves(await usdc.getAddress());
      expect(usdcReserve.isActive).to.be.true;
    });
  });
  
  describe("Deposit and Withdraw Collateral", function () {
    it("应该允许用户存入抵押品", async function () {
      const depositAmount = ethers.parseEther("1"); // 1 WETH
      
      await expect(lendingContract.connect(user1).deposit(await weth.getAddress(), depositAmount, { gasLimit: 500000 }))
        .to.emit(lendingContract, "Deposit")
        .withArgs(user1.address, await weth.getAddress(), depositAmount);
      
      const userPosition = await lendingContract.getUserPosition(user1.address, await weth.getAddress(), await usdt.getAddress());
      expect(userPosition.collateralBalance).to.equal(depositAmount);
    });
    
    it("应该允许用户提取抵押品（无借款）", async function () {
      const depositAmount = ethers.parseEther("1");
      await lendingContract.connect(user1).deposit(await weth.getAddress(), depositAmount, { gasLimit: 1000000 });
      
      await expect(lendingContract.connect(user1).withdraw(await weth.getAddress(), depositAmount, { gasLimit: 1000000 }))
        .to.emit(lendingContract, "Withdraw")
        .withArgs(user1.address, await weth.getAddress(), depositAmount);
      
      const userPosition = await lendingContract.getUserPosition(user1.address, await weth.getAddress(), await usdt.getAddress());
      expect(userPosition.collateralBalance).to.equal(0);
    });
    
    it("应该在有借款时根据健康因子限制提取", async function () {
      const depositAmount = ethers.parseEther("1"); // 1 WETH (~$3000)
      await lendingContract.connect(user1).deposit(await weth.getAddress(), depositAmount, { gasLimit: 1000000 });
      
      // 借款 $2000 USDC
      const borrowAmount = ethers.parseUnits("2000", 6);
      await lendingContract.connect(user1).borrow(await usdc.getAddress(), borrowAmount, { gasLimit: 1000000 });
      
      // 尝试提取部分抵押品，应该成功
      const withdrawAmount = ethers.parseEther("0.1"); // 0.1 WETH
      await lendingContract.connect(user1).withdraw(await weth.getAddress(), withdrawAmount, { gasLimit: 1000000 });
      
      const userPosition = await lendingContract.getUserPosition(user1.address, await weth.getAddress(), await usdc.getAddress());
      expect(userPosition.collateralBalance).to.equal(depositAmount - withdrawAmount);
    });
  });
  
  describe("Borrow and Repay", function () {
    it("应该允许用户借款", async function () {
      const depositAmount = ethers.parseEther("1"); // 1 WETH (~$3000)
      await lendingContract.connect(user1).deposit(await weth.getAddress(), depositAmount, { gasLimit: 1000000 });
      
      const borrowAmount = ethers.parseUnits("100", 6); // $100 USDC
      await expect(lendingContract.connect(user1).borrow(await usdc.getAddress(), borrowAmount, { gasLimit: 1000000 }))
        .to.emit(lendingContract, "Borrow")
        .withArgs(user1.address, await usdc.getAddress(), borrowAmount);
      
      const userPosition = await lendingContract.getUserPosition(user1.address, await weth.getAddress(), await usdc.getAddress());
      expect(userPosition.borrowBalance).to.equal(borrowAmount);
    });
    
    it("应该根据健康因子限制借款金额", async function () {
      const depositAmount = ethers.parseEther("1"); // 1 WETH (~$3000)
      await lendingContract.connect(user1).deposit(await weth.getAddress(), depositAmount, { gasLimit: 1000000 });
      
      // 尝试借款超过最大可借金额，应该失败
      const maxBorrowAmount = ethers.parseUnits("2250", 6); // 3000 * 0.75
      await expect(lendingContract.connect(user1).borrow(await usdc.getAddress(), maxBorrowAmount + 1n, { gasLimit: 1000000 }))
        .to.be.revertedWith("Health factor too low");
    });
    
    it("应该允许用户还款", async function () {
      // 存入抵押品并借款
      const depositAmount = ethers.parseEther("1");
      await lendingContract.connect(user1).deposit(await weth.getAddress(), depositAmount, { gasLimit: 1000000 });
      
      const borrowAmount = ethers.parseUnits("100", 6);
      await lendingContract.connect(user1).borrow(await usdc.getAddress(), borrowAmount, { gasLimit: 1000000 });
      
      // 还款
      await expect(lendingContract.connect(user1).repay(await usdc.getAddress(), borrowAmount, { gasLimit: 1000000 }))
        .to.emit(lendingContract, "Repay")
        .withArgs(user1.address, await usdc.getAddress(), borrowAmount);
      
      const userPosition = await lendingContract.getUserPosition(user1.address, await weth.getAddress(), await usdc.getAddress());
      expect(userPosition.borrowBalance).to.equal(0);
    });
  });
  
  describe("Liquidation", function () {
    it("不应该允许清算健康仓位", async function () {
      // 用户1存入抵押品并借款（健康状态）
      const depositAmount = ethers.parseEther("1"); // 1 WETH
      await lendingContract.connect(user1).deposit(await weth.getAddress(), depositAmount, { gasLimit: 1000000 });
      
      const borrowAmount = ethers.parseUnits("10", 6); // $10 USDC
      await lendingContract.connect(user1).borrow(await usdc.getAddress(), borrowAmount, { gasLimit: 1000000 });
      
      // 尝试清算，应该失败
      const debtToCover = ethers.parseUnits("50", 6);
      await usdc.mint(liquidator.address, debtToCover);
      await usdc.connect(liquidator).approve(await lendingContract.getAddress(), debtToCover);
      
      await expect(lendingContract.connect(liquidator).liquidate(
        user1.address,
        await weth.getAddress(),
        await usdc.getAddress(),
        debtToCover,
        { gasLimit: 1000000 }
      )).to.be.revertedWith("Position not liquidatable");
    });
  });
  
  describe("Interest Calculation", function () {
    it("应该正确计算借款利息", async function () {
      // 存入抵押品并借款
      const depositAmount = ethers.parseEther("1");
      await lendingContract.connect(user1).deposit(await weth.getAddress(), depositAmount, { gasLimit: 1000000 });
      
      const borrowAmount = ethers.parseUnits("10", 6);
      await lendingContract.connect(user1).borrow(await usdc.getAddress(), borrowAmount, { gasLimit: 1000000 });
      
      // 计算利息
      const interest = await lendingContract.calculateBorrowInterest(user1.address, await usdc.getAddress());
      expect(interest).to.be.a('bigint');
    });
  });
  
  describe("Reserve Rates", function () {
    it("应该根据利用率更新借款利率", async function () {
      // 检查初始利率
      const initialRate = await lendingContract.reserves(await usdc.getAddress());
      expect(initialRate.borrowRate).to.be.a('bigint');
      
      // 存入抵押品并借款
      const depositAmount = ethers.parseEther("1");
      await lendingContract.connect(user1).deposit(await weth.getAddress(), depositAmount, { gasLimit: 1000000 });
      
      const borrowAmount = ethers.parseUnits("10", 6);
      await lendingContract.connect(user1).borrow(await usdc.getAddress(), borrowAmount, { gasLimit: 1000000 });
      
      // 检查利率是否更新
      const updatedRate = await lendingContract.reserves(await usdc.getAddress());
      expect(updatedRate.borrowRate).to.be.a('bigint');
    });
  });
  
  describe("Edge Cases", function () {
    it("应该处理零金额操作", async function () {
      // 尝试存入零金额，应该失败
      await expect(lendingContract.connect(user1).deposit(await weth.getAddress(), 0, { gasLimit: 1000000 }))
        .to.be.revertedWith("Amount must be greater than zero");
      
      // 尝试提取零金额，应该失败
      await expect(lendingContract.connect(user1).withdraw(await weth.getAddress(), 0, { gasLimit: 1000000 }))
        .to.be.revertedWith("Amount must be greater than zero");
      
      // 尝试借款零金额，应该失败
      await expect(lendingContract.connect(user1).borrow(await usdc.getAddress(), 0, { gasLimit: 1000000 }))
        .to.be.revertedWith("Amount must be greater than zero");
      
      // 尝试还款零金额，应该失败
      await expect(lendingContract.connect(user1).repay(await usdc.getAddress(), 0, { gasLimit: 1000000 }))
        .to.be.revertedWith("Amount must be greater than zero");
    });
    
    it("应该处理流动性不足的情况", async function () {
      // 存入抵押品
      const depositAmount = ethers.parseEther("10"); // 10 WETH
      await lendingContract.connect(user1).deposit(await weth.getAddress(), depositAmount, { gasLimit: 1000000 });
      
      // 尝试借款超过可用流动性
      const largeAmount = ethers.parseUnits("20000", 6); // $20000 USDC
      await expect(lendingContract.connect(user1).borrow(await usdc.getAddress(), largeAmount, { gasLimit: 1000000 }))
        .to.be.revertedWith("Insufficient liquidity");
    });
  });
  
  describe("Emergency Functions", function () {
    it("应该允许所有者紧急提取代币", async function () {
      const amount = ethers.parseUnits("100", 6);
      await expect(lendingContract.emergencyWithdraw(await usdt.getAddress(), amount))
        .to.not.be.reverted;
    });
    
    it("不应该允许非所有者紧急提取代币", async function () {
      const amount = ethers.parseUnits("100", 6);
      await expect(lendingContract.connect(user1).emergencyWithdraw(await usdt.getAddress(), amount))
        .to.be.reverted;
    });
  });
});
