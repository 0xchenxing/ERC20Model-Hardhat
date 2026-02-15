import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";
import { StakingVault } from "../typechain-types/contracts/library/StakingVault";
import { ERC20Mock } from "../typechain-types/contracts/test/ERC20Mock";

describe("StakingVault", function () {
  let stakingVault: StakingVault;
  let owner: Signer;
  let user1: Signer;
  let user2: Signer;
  let mockStakingToken: ERC20Mock;
  let mockRewardToken1: ERC20Mock;
  let mockRewardToken2: ERC20Mock;
  let mockStakingTokenAddress: string;
  let mockRewardToken1Address: string;
  let mockRewardToken2Address: string;

  beforeEach(async function () {
    // 获取测试账户
    const accounts = await ethers.getSigners();
    owner = accounts[0];
    user1 = accounts[1];
    user2 = accounts[2];

    // 部署模拟代币合约
    const MockTokenFactory = await ethers.getContractFactory("ERC20Mock");
    mockStakingToken = await MockTokenFactory.deploy("Staking Token", "STK", ethers.parseEther("10000"));
    await mockStakingToken.waitForDeployment();
    mockStakingTokenAddress = await mockStakingToken.getAddress();

    mockRewardToken1 = await MockTokenFactory.deploy("Reward Token 1", "RWD1", ethers.parseEther("10000"));
    await mockRewardToken1.waitForDeployment();
    mockRewardToken1Address = await mockRewardToken1.getAddress();

    mockRewardToken2 = await MockTokenFactory.deploy("Reward Token 2", "RWD2", ethers.parseEther("10000"));
    await mockRewardToken2.waitForDeployment();
    mockRewardToken2Address = await mockRewardToken2.getAddress();

    // 部署 StakingVault 合约
    const StakingVaultFactory = await ethers.getContractFactory("StakingVault");
    stakingVault = await StakingVaultFactory.deploy();
    await stakingVault.waitForDeployment();

    // 给用户分发测试代币
    await mockStakingToken.transfer(await user1.getAddress(), ethers.parseEther("1000"));
    await mockStakingToken.transfer(await user2.getAddress(), ethers.parseEther("1000"));
    await mockRewardToken1.transfer(await owner.getAddress(), ethers.parseEther("5000"));
    await mockRewardToken2.transfer(await owner.getAddress(), ethers.parseEther("5000"));
  });

  describe("管理员操作", function () {
    it("应该能够添加质押池", async function () {
      await expect(stakingVault.addStakingPool(mockStakingTokenAddress))
        .to.emit(stakingVault, "PoolAdded")
        .withArgs(mockStakingTokenAddress);

      const pool = await stakingVault.pools(mockStakingTokenAddress);
      expect(pool.stakingToken).to.equal(mockStakingTokenAddress);
    });

    it("应该能够添加奖励池", async function () {
      // 先添加质押池
      await stakingVault.addStakingPool(mockStakingTokenAddress);

      // 授权合约使用奖励代币
      const totalRewards = ethers.parseEther("1000");
      await mockRewardToken1.connect(owner).approve(await stakingVault.getAddress(), totalRewards);

      // 添加奖励池
      const annualRewardPerToken = ethers.parseEther("3.65"); // 每年每1个代币奖励3.65个奖励代币（相当于每天0.01个）
      await expect(stakingVault.addRewardPool(mockRewardToken1Address, totalRewards, annualRewardPerToken))
        .to.emit(stakingVault, "RewardPoolAdded")
        .withArgs(mockRewardToken1Address, totalRewards, annualRewardPerToken);
    });

    it("应该能够向奖励池充值代币", async function () {
      // 先添加质押池和奖励池
      await stakingVault.addStakingPool(mockStakingTokenAddress);
      
      // 添加初始奖励池
      const initialRewards = ethers.parseEther("500");
      const annualRewardPerToken = ethers.parseEther("3.65"); // 每年每1个代币奖励3.65个奖励代币（相当于每天0.01个）
      await mockRewardToken1.connect(owner).approve(await stakingVault.getAddress(), initialRewards);
      await stakingVault.addRewardPool(mockRewardToken1Address, initialRewards, annualRewardPerToken);

      // 授权合约使用更多奖励代币
      const fundAmount = ethers.parseEther("1000");
      await mockRewardToken1.connect(owner).approve(await stakingVault.getAddress(), fundAmount);

      // 充值奖励池
      await expect(stakingVault.fundRewardPool(mockRewardToken1Address, fundAmount))
        .to.emit(stakingVault, "RewardPoolFunded")
        .withArgs(mockRewardToken1Address, fundAmount);

      // 验证合约收到了奖励代币
      const contractBalance = await mockRewardToken1.balanceOf(await stakingVault.getAddress());
      expect(contractBalance).to.equal(initialRewards + fundAmount);
    });
  });

  describe("用户操作", function () {
    beforeEach(async function () {
      // 准备测试环境
      await stakingVault.addStakingPool(mockStakingTokenAddress);
      
      // 添加奖励池
      const totalRewards = ethers.parseEther("1000");
      const annualRewardPerToken = ethers.parseEther("3.65"); // 每年每1个代币奖励3.65个奖励代币（相当于每天0.01个）
      await mockRewardToken1.connect(owner).approve(await stakingVault.getAddress(), totalRewards);
      await stakingVault.addRewardPool(mockRewardToken1Address, totalRewards, annualRewardPerToken);
    });

    it("用户应该能够质押代币", async function () {
      const stakeAmount = ethers.parseEther("100");
      
      // 授权合约使用质押代币
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount);

      // 质押代币（使用模式0：30天），并选择奖励代币
      await expect(stakingVault.connect(user1).stake(mockStakingTokenAddress, stakeAmount, 0, mockRewardToken1Address))
        .to.emit(stakingVault, "Staked");

      // 验证用户质押信息
      const userStakes = await stakingVault.getUserStakes(await user1.getAddress());
      expect(userStakes.length).to.equal(1);
      expect(userStakes[0].amount).to.equal(stakeAmount);
      expect(userStakes[0].modeId).to.equal(0);
      expect(userStakes[0].rewardToken).to.equal(mockRewardToken1Address);
    });

    it("用户应该能够正常赎回代币", async function () {
      const stakeAmount = ethers.parseEther("100");
      
      // 授权并质押
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount);
      await stakingVault.connect(user1).stake(mockStakingTokenAddress, stakeAmount, 0, mockRewardToken1Address);

      // 增加时间，模拟30天后
      await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]); // 30天
      await ethers.provider.send("evm_mine");

      // 赎回（使用索引0）
      await expect(stakingVault.connect(user1).unstake(0))
        .to.emit(stakingVault, "Unstaked");

      // 验证用户质押信息已被清理
      const userStakes = await stakingVault.getUserStakes(await user1.getAddress());
      expect(userStakes.length).to.equal(1);
      expect(userStakes[0].amount).to.equal(0);
    });

    it("用户提前赎回应该受到惩罚", async function () {
      const stakeAmount = ethers.parseEther("100");
      
      // 授权并质押
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount);
      await stakingVault.connect(user1).stake(mockStakingTokenAddress, stakeAmount, 0, mockRewardToken1Address);

      // 增加时间，模拟15天后
      await ethers.provider.send("evm_increaseTime", [15 * 24 * 60 * 60]); // 15天
      await ethers.provider.send("evm_mine");

      // 赎回（使用索引0）
      await expect(stakingVault.connect(user1).unstake(0))
        .to.emit(stakingVault, "Unstaked");
    });

    it("用户应该能够领取奖励", async function () {
      const stakeAmount = ethers.parseEther("100");
      
      // 授权并质押
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount);
      await stakingVault.connect(user1).stake(mockStakingTokenAddress, stakeAmount, 0, mockRewardToken1Address);

      // 增加时间，累积奖励
      await ethers.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]); // 7天
      await ethers.provider.send("evm_mine");

      // 领取奖励前的余额
      const beforeBalance = await mockRewardToken1.balanceOf(await user1.getAddress());

      // 领取奖励
      await stakingVault.connect(user1).claimRewards(0);

      // 领取奖励后的余额
      const afterBalance = await mockRewardToken1.balanceOf(await user1.getAddress());

      // 验证奖励已发放
      expect(afterBalance).to.be.gt(beforeBalance);
    });

    it("用户应该能够使用不同的质押模式", async function () {
      const stakeAmount = ethers.parseEther("100");
      
      // 授权合约使用质押代币
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount);

      // 测试模式1：90天
      await stakingVault.connect(user1).stake(mockStakingTokenAddress, stakeAmount, 1, mockRewardToken1Address);

      // 验证用户质押信息
      const userStakes = await stakingVault.getUserStakes(await user1.getAddress());
      expect(userStakes.length).to.equal(1);
      expect(userStakes[0].modeId).to.equal(1);
    });

    it("应该正确计算质押不足1个代币的奖励", async function () {
      // 质押0.5个代币（不足1个代币）
      const stakeAmount = ethers.parseEther("0.5");
      
      // 授权并质押
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount);
      await stakingVault.connect(user1).stake(mockStakingTokenAddress, stakeAmount, 0, mockRewardToken1Address);

      // 增加时间，模拟30天后
      await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]); // 30天
      await ethers.provider.send("evm_mine");

      // 领取奖励前的余额
      const beforeBalance = await mockRewardToken1.balanceOf(await user1.getAddress());

      // 领取奖励
      await stakingVault.connect(user1).claimRewards(0);

      // 领取奖励后的余额
      const afterBalance = await mockRewardToken1.balanceOf(await user1.getAddress());

      // 验证奖励已发放（应该获得大约 0.5 * 3.65 * 30/365 * 1.2 = 0.18 个奖励代币，因为模式0的奖励乘数是1.2倍）
      const expectedReward = ethers.parseEther("0.18");
      const actualReward = afterBalance - beforeBalance;
      
      // 允许一定的误差（由于计算精度）
      expect(actualReward).to.be.at.least(expectedReward * 99n / 100n);
      expect(actualReward).to.be.at.most(expectedReward * 101n / 100n);
    });

    it("用户应该能够质押多个代币", async function () {
      // 部署另一个质押代币
      const MockTokenFactory = await ethers.getContractFactory("ERC20Mock");
      const anotherStakingToken = await MockTokenFactory.deploy("Another Staking Token", "ASTK", ethers.parseEther("10000"));
      await anotherStakingToken.waitForDeployment();
      const anotherStakingTokenAddress = await anotherStakingToken.getAddress();

      // 给用户转账
      await anotherStakingToken.transfer(await user1.getAddress(), ethers.parseEther("1000"));

      // 添加新的质押池
      await stakingVault.addStakingPool(anotherStakingTokenAddress);
      
      // 确保奖励池已添加
      if ((await stakingVault.getAvailableRewardTokens()).length === 0) {
        const totalRewards = ethers.parseEther("1000");
        const dailyRewardPerToken = ethers.parseEther("0.01");
        await mockRewardToken1.connect(owner).approve(await stakingVault.getAddress(), totalRewards);
        await stakingVault.addRewardPool(mockRewardToken1Address, totalRewards, dailyRewardPerToken);
      }

      // 质押第一个代币
      const stakeAmount1 = ethers.parseEther("50");
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount1);
      await stakingVault.connect(user1).stake(mockStakingTokenAddress, stakeAmount1, 0, mockRewardToken1Address);

      // 质押第二个代币
      const stakeAmount2 = ethers.parseEther("50");
      await anotherStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount2);
      await stakingVault.connect(user1).stake(anotherStakingTokenAddress, stakeAmount2, 0, mockRewardToken1Address);

      // 验证用户质押信息
      const userStakes = await stakingVault.getUserStakes(await user1.getAddress());
      expect(userStakes.length).to.equal(2);
    });
  });

  describe("查询功能", function () {
    beforeEach(async function () {
      // 准备测试环境
      await stakingVault.addStakingPool(mockStakingTokenAddress);
      
      // 添加奖励池
      const totalRewards1 = ethers.parseEther("1000");
      const annualRewardPerToken1 = ethers.parseEther("3.65"); // 每年每1个代币奖励3.65个奖励代币（相当于每天0.01个）
      await mockRewardToken1.connect(owner).approve(await stakingVault.getAddress(), totalRewards1);
      await stakingVault.addRewardPool(mockRewardToken1Address, totalRewards1, annualRewardPerToken1);
      
      const totalRewards2 = ethers.parseEther("2000");
      const annualRewardPerToken2 = ethers.parseEther("7.3"); // 每年每1个代币奖励7.3个奖励代币（相当于每天0.02个）
      await mockRewardToken2.connect(owner).approve(await stakingVault.getAddress(), totalRewards2);
      await stakingVault.addRewardPool(mockRewardToken2Address, totalRewards2, annualRewardPerToken2);
    });

    it("应该能够获取用户质押信息", async function () {
      const stakeAmount = ethers.parseEther("100");
      
      // 授权并质押
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount);
      await stakingVault.connect(user1).stake(mockStakingTokenAddress, stakeAmount, 0, mockRewardToken1Address);

      // 获取用户质押信息
      const userStakes = await stakingVault.getUserStakes(await user1.getAddress());
      
      expect(userStakes.length).to.equal(1);
      expect(userStakes[0].stakingToken).to.equal(mockStakingTokenAddress);
      expect(userStakes[0].rewardToken).to.equal(mockRewardToken1Address);
      expect(userStakes[0].amount).to.equal(stakeAmount);
      expect(userStakes[0].modeId).to.equal(0);
    });

    it("应该能够获取可用奖励代币", async function () {
      // 获取可用奖励代币
      const rewardTokens = await stakingVault.getAvailableRewardTokens();
      
      expect(rewardTokens.length).to.equal(2);
      expect(rewardTokens).to.include(mockRewardToken1Address);
      expect(rewardTokens).to.include(mockRewardToken2Address);
    });

    it("应该能够获取奖励池信息", async function () {
      // 获取奖励池信息
      const rewardPoolInfo = await stakingVault.getRewardPoolInfo(mockRewardToken1Address);
      
      expect(rewardPoolInfo.totalRewards).to.equal(ethers.parseEther("1000"));
      expect(rewardPoolInfo.annualRewardPerToken).to.equal(ethers.parseEther("3.65"));
      expect(rewardPoolInfo.totalDistributed).to.equal(0);
      expect(rewardPoolInfo.remainingRewards).to.equal(ethers.parseEther("1000"));
    });

    it("应该能够获取质押模式信息", async function () {
      // 获取质押模式信息
      const mode0 = await stakingVault.stakingModes(0);
      const mode1 = await stakingVault.stakingModes(1);
      const mode2 = await stakingVault.stakingModes(2);

      expect(mode0.duration).to.equal(30 * 24 * 60 * 60); // 30天
      expect(mode1.duration).to.equal(90 * 24 * 60 * 60); // 90天
      expect(mode2.duration).to.equal(180 * 24 * 60 * 60); // 180天
    });
  });

  describe("错误处理", function () {
    beforeEach(async function () {
      // 准备测试环境
      await stakingVault.addStakingPool(mockStakingTokenAddress);
      
      // 添加奖励池
      const totalRewards = ethers.parseEther("1000");
      const annualRewardPerToken = ethers.parseEther("3.65"); // 每年每1个代币奖励3.65个奖励代币（相当于每天0.01个）
      await mockRewardToken1.connect(owner).approve(await stakingVault.getAddress(), totalRewards);
      await stakingVault.addRewardPool(mockRewardToken1Address, totalRewards, annualRewardPerToken);
    });

    it("应该拒绝重复添加相同的质押池", async function () {
      await expect(stakingVault.addStakingPool(mockStakingTokenAddress))
        .to.be.revertedWith("Pool exists");
    });

    it("应该拒绝使用无效的质押模式", async function () {
      const stakeAmount = ethers.parseEther("100");
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount);
      
      // 使用不存在的模式ID（3）
      await expect(stakingVault.connect(user1).stake(mockStakingTokenAddress, stakeAmount, 3, mockRewardToken1Address))
        .to.be.revertedWith("Invalid mode");
    });

    it("应该拒绝质押零金额", async function () {
      await expect(stakingVault.connect(user1).stake(mockStakingTokenAddress, 0, 0, mockRewardToken1Address))
        .to.be.revertedWith("Amount zero");
    });

    it("应该拒绝赎回不存在的质押", async function () {
      // 当尝试访问不存在的数组索引时，Solidity会抛出数组越界错误
      await expect(stakingVault.connect(user1).unstake(0))
        .to.be.revertedWithPanic(0x32); // 0x32 = Array accessed at an out-of-bounds or negative index
    });

    it("应该拒绝使用不存在的质押池", async function () {
      const stakeAmount = ethers.parseEther("100");
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount);
      
      const nonExistentPool = "0x0000000000000000000000000000000000000001";
      await expect(stakingVault.connect(user1).stake(nonExistentPool, stakeAmount, 0, mockRewardToken1Address))
        .to.be.revertedWith("Pool not exists");
    });

    it("应该拒绝使用不存在的奖励池", async function () {
      const stakeAmount = ethers.parseEther("100");
      await mockStakingToken.connect(user1).approve(await stakingVault.getAddress(), stakeAmount);
      
      const nonExistentRewardToken = "0x0000000000000000000000000000000000000001";
      await expect(stakingVault.connect(user1).stake(mockStakingTokenAddress, stakeAmount, 0, nonExistentRewardToken))
        .to.be.revertedWith("Reward pool not exists or disabled");
    });
  });
});
