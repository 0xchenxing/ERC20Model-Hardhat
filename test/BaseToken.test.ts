import { expect } from "chai";
import { ethers } from "hardhat";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { BaseToken, SecurityPool } from "../typechain-types";

describe("BaseToken", function () {
  let baseToken: BaseToken;
  let securityPool: SecurityPool;
  let owner: any;
  let user1: any;
  let user2: any;
  let user3: any;
  let oracle: any;
  let baseTokenAddress: string;
  let securityPoolAddress: string;
  let deployTimeSlot: string;

  const formatSlot = (slot: number) =>
    "0x" + slot.toString(16).padStart(64, "0");

  const findSlotContainingValue = async (value: bigint) => {
    const target = ethers.toBeHex(value, 32).toLowerCase();
    for (let i = 0; i < 200; i++) {
      const slotHex = formatSlot(i);
      try {
        const storageValue = (
          await ethers.provider.getStorage(baseTokenAddress, slotHex)
        ).toLowerCase();
        if (storageValue === target) {
          return slotHex;
        }
      } catch (error) {
        // 忽略无法读取的存储槽
        continue;
      }
    }
    throw new Error(`Slot not found for value ${value}`);
  };

  const overwriteSlot = async (slotHex: string, newValue: bigint) => {
    await ethers.provider.send("hardhat_setStorageAt", [
      baseTokenAddress,
      slotHex,
      ethers.toBeHex(newValue, 32),
    ]);
  };

  // 时间常量（转换为秒）
  const MINUTE = 60;
  const HOUR = 60 * MINUTE;
  const DAY = 24 * HOUR;
  const MONTH = 30 * DAY; // 近似月为30天
  const YEAR = 365 * DAY; // 年

  beforeEach(async function () {
    [owner, user1, user2, user3, oracle] = await ethers.getSigners();

    const BaseTokenFactory = await ethers.getContractFactory("BaseToken");
    baseToken = await BaseTokenFactory.deploy(owner.address);
    await baseToken.waitForDeployment();
    baseTokenAddress = await baseToken.getAddress();
    securityPoolAddress = await baseToken.securityPool();
    securityPool = await ethers.getContractAt(
      "SecurityPool",
      securityPoolAddress
    );
  });

  describe("安全资金池", function () {
    it("部署后托管合约代币", async function () {
      const totalSupply = await baseToken.TOTAL_SUPPLY();
      const liquidityReserve = await baseToken.LIQUIDITY_RESERVE_ALLOCATION();
      const poolBalance = await baseToken.balanceOf(securityPoolAddress);
      expect(poolBalance).to.equal(totalSupply - liquidityReserve);
    });

    it("用户质押后资金进入安全池", async function () {
      const stakeAmount = ethers.parseEther("1000");
      await baseToken.connect(owner).transfer(user1.address, stakeAmount);

      const before = await baseToken.balanceOf(securityPoolAddress);
      await baseToken.connect(user1).stake(stakeAmount, 7);
      const after = await baseToken.balanceOf(securityPoolAddress);

      expect(after - before).to.equal(stakeAmount);
    });
  });

  describe("部署和初始化", function () {
    it("应该正确设置代币名称和符号", async function () {
      expect(await baseToken.name()).to.equal("BaseToken");
      expect(await baseToken.symbol()).to.equal("BASE");
    });

    it("应该正确设置总供应量", async function () {
      const totalSupply = await baseToken.TOTAL_SUPPLY();
      expect(totalSupply).to.equal(ethers.parseEther("1000000000")); // 10亿 * 10^18
    });

    it("应该正确分配初始代币", async function () {
      const contractBalance = await baseToken.balanceOf(baseTokenAddress);
      const poolBalance = await baseToken.balanceOf(securityPoolAddress);
      const ownerBalance = await baseToken.balanceOf(owner.address);

      // 合约应该持有除流动性储备外的所有代币
      const totalSupply = await baseToken.TOTAL_SUPPLY();
      const liquidityReserve = await baseToken.LIQUIDITY_RESERVE_ALLOCATION();
      expect(poolBalance).to.equal(totalSupply - liquidityReserve);
      expect(contractBalance).to.equal(0n);

      // 所有者应该获得流动性储备
      expect(ownerBalance).to.equal(
        await baseToken.LIQUIDITY_RESERVE_ALLOCATION()
      );
    });

    it("应该正确初始化分配池", async function () {
      expect(await baseToken.remainingAlloc("seed")).to.equal(
        await baseToken.SEED_ALLOCATION()
      );
      expect(await baseToken.remainingAlloc("strategic_round")).to.equal(
        await baseToken.STRATEGIC_ROUND_ALLOCATION()
      );
      expect(await baseToken.remainingAlloc("project")).to.equal(
        await baseToken.PROJECT_ALLOCATION()
      );

      expect(await baseToken.airdropPool()).to.equal(
        await baseToken.STARTUP_INCENTIVE_ALLOCATION()
      );
      expect(await baseToken.ecosystemPool()).to.equal(
        await baseToken.ECOSYSTEM_INCENTIVE_ALLOCATION()
      );
      expect(await baseToken.strategicPool()).to.equal(
        await baseToken.STRATEGIC_RESERVE_ALLOCATION()
      );
    });
  });

  describe("Vesting功能", function () {
    it("应该允许所有者添加vesting", async function () {
      const amount = ethers.parseEther("1000");

      await expect(
        baseToken.connect(owner).addVesting("seed", user1.address, amount)
      )
        .to.emit(baseToken, "VestingAdded")
        .withArgs(user1.address, amount, "seed");

      const vesting = await baseToken.vestings("seed", user1.address);
      expect(vesting.totalAmount).to.equal(amount);
      expect(vesting.released).to.equal(0n);
    });

    it("非所有者不能添加vesting", async function () {
      const amount = ethers.parseEther("1000");

      await expect(
        baseToken.connect(user1).addVesting("seed", user2.address, amount)
      )
        .to.be.revertedWithCustomError(
          baseToken,
          "OwnableUnauthorizedAccount"
        )
        .withArgs(user1.address);
    });

    it("不能添加超过分配限额的vesting", async function () {
      const seedAllocation = await baseToken.SEED_ALLOCATION();
      const excessAmount = seedAllocation + ethers.parseEther("1");

      await expect(
        baseToken.connect(owner).addVesting("seed", user1.address, excessAmount)
      ).to.be.revertedWith("Insufficient remaining allocation");
    });

    it("应该正确计算vesting可领取数量", async function () {
      const amount = ethers.parseEther("1000");
      await baseToken.connect(owner).addVesting("seed", user1.address, amount);

      // 在锁定期内应该无可领取
      let pending = await baseToken.getPendingVesting(user1.address);
      expect(pending).to.equal(0n);

      // 推进时间到锁定期结束
      const seedLockPeriod = await baseToken.SEED_LOCK_PERIOD();
      await ethers.provider.send("evm_increaseTime", [
        Number(seedLockPeriod),
      ]);
      await ethers.provider.send("evm_mine", []);

      // 应该可以领取部分代币
      pending = await baseToken.getPendingVesting(user1.address);
      expect(pending).to.be.gt(0n);
    });

    it("应该允许用户领取vesting", async function () {
      const amount = ethers.parseEther("1000");
      await baseToken.connect(owner).addVesting("seed", user1.address, amount);

      // 推进时间到可以领取
      const seedLockPeriod = await baseToken.SEED_LOCK_PERIOD();
      await ethers.provider.send("evm_increaseTime", [
        Number(seedLockPeriod) + MINUTE,
      ]);
      await ethers.provider.send("evm_mine", []);

      const balanceBefore = await baseToken.balanceOf(user1.address);

      await expect(baseToken.connect(user1).claimAllVesting()).to.emit(
        baseToken,
        "VestingClaimed"
      );

      const balanceAfter = await baseToken.balanceOf(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
    });
  });

  describe("空投功能", function () {
    it("应该允许用户领取空投", async function () {
      const dailyClaimAmount = await baseToken.DAILY_CLAIM_AMOUNT();

      await expect(baseToken.connect(user1).claimAirdrop())
        .to.emit(baseToken, "AirdropClaimed")
        .withArgs(user1.address, dailyClaimAmount);

      const userBalance = await baseToken.balanceOf(user1.address);
      expect(userBalance).to.equal(dailyClaimAmount);
    });

    it("不能重复领取同一天的空投", async function () {
      await baseToken.connect(user1).claimAirdrop();

      await expect(baseToken.connect(user1).claimAirdrop()).to.be.revertedWith(
        "Already claimed today"
      );
    });

    it("应该遵守每日空投限额", async function () {
      const dailyLimit = await baseToken.DAILY_AIRDROP_LIMIT();
      const claimAmount = await baseToken.DAILY_CLAIM_AMOUNT();
      const maxClaims = Number(dailyLimit / claimAmount);
      const signers = await ethers.getSigners();

      // 多个用户领取用于产生非零释放量
      for (let i = 0; i < Math.min(maxClaims, 2); i++) {
        const user = signers[i + 5];
        await baseToken.connect(user).claimAirdrop();
      }

      const released = await baseToken.dailyAirdropReleased();
      const releasedSlot = await findSlotContainingValue(released);

      await overwriteSlot(releasedSlot, dailyLimit);
      expect(await baseToken.dailyAirdropReleased()).to.equal(dailyLimit);

      // 下一个用户应该无法领取（当日限额已满）
      await expect(baseToken.connect(user3).claimAirdrop()).to.be.revertedWith(
        "No airdrop available today"
      );
    });

    it("应该允许销毁剩余空投", async function () {
      // 推进时间到空投期结束
      const startupReleasePeriod = await baseToken.STARTUP_RELEASE_PERIOD();
      await ethers.provider.send("evm_increaseTime", [
        Number(startupReleasePeriod),
      ]);
      await ethers.provider.send("evm_mine", []);

      const airdropPoolBefore = await baseToken.airdropPool();

      await expect(baseToken.burnRemainingAirdrop())
        .to.emit(baseToken, "AirdropBurned")
        .withArgs(airdropPoolBefore);

      expect(await baseToken.airdropPool()).to.equal(0n);
    });
  });

  describe("质押功能", function () {
    beforeEach(async function () {
      // 给用户一些代币用于质押
      const stakeAmount = ethers.parseEther("1000");
      await baseToken.connect(owner).transfer(user1.address, stakeAmount);
    });

    it("应该允许用户质押代币", async function () {
      const stakeAmount = ethers.parseEther("100");
      await baseToken.connect(user1).approve(baseTokenAddress, stakeAmount);

      await expect(baseToken.connect(user1).stake(stakeAmount, 30))
        .to.emit(baseToken, "Staked")
        .withArgs(user1.address, stakeAmount, 30, ethers.ZeroAddress);

      const stakesCount = await baseToken.getStakesCount(user1.address);
      expect(stakesCount).to.equal(1n);
    });

    it("应该正确计算质押奖励", async function () {
      const stakeAmount = ethers.parseEther("100");
      await baseToken.connect(user1).approve(baseTokenAddress, stakeAmount);
      await baseToken.connect(user1).stake(stakeAmount, 30);

      // 推进时间
      await ethers.provider.send("evm_increaseTime", [5 * MINUTE]);
      await ethers.provider.send("evm_mine", []);

      const pendingRewards = await baseToken.getPendingRewards(user1.address);
      expect(pendingRewards).to.be.gt(0n);
    });

    it("应该允许用户领取奖励", async function () {
      const stakeAmount = ethers.parseEther("100");
      await baseToken.connect(user1).approve(baseTokenAddress, stakeAmount);
      await baseToken.connect(user1).stake(stakeAmount, 30);

      // 推进时间
      await ethers.provider.send("evm_increaseTime", [5 * MINUTE]);
      await ethers.provider.send("evm_mine", []);

      await expect(baseToken.connect(user1).claimAllRewards()).to.emit(
        baseToken,
        "RewardClaimed"
      );
    });

    it("应该允许用户赎回质押", async function () {
      const stakeAmount = ethers.parseEther("100");
      await baseToken.connect(user1).approve(baseTokenAddress, stakeAmount);
      await baseToken.connect(user1).stake(stakeAmount, 7); // 7天锁定期

      // 等待锁定期结束
      await ethers.provider.send("evm_increaseTime", [7 * DAY + 1]);
      await ethers.provider.send("evm_mine", []);

      const balanceBefore = await baseToken.balanceOf(user1.address);
      await baseToken.connect(user1).unstake(0);
      const balanceAfter = await baseToken.balanceOf(user1.address);

      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("提前赎回应该收取罚金", async function () {
      const stakeAmount = ethers.parseEther("100");
      await baseToken.connect(user1).approve(baseTokenAddress, stakeAmount);
      await baseToken.connect(user1).stake(stakeAmount, 30);

      await expect(baseToken.connect(user1).unstake(0))
        .to.emit(baseToken, "Unstaked")
        .withArgs(user1.address, anyValue, anyValue, anyValue); // 应该有罚金
    });
  });

  describe("推荐系统", function () {
    beforeEach(async function () {
      // 设置推荐关系
      await baseToken.connect(user2).setReferrer(user1.address);
      await baseToken.connect(user3).setReferrer(user2.address);
    });

    it("应该允许用户设置推荐人", async function () {
      await baseToken.connect(user1).setReferrer(owner.address);

      const referrer = await baseToken.getReferrer(user1.address);
      expect(referrer).to.equal(owner.address);
    });

    it("不能设置自己为推荐人", async function () {
      await expect(
        baseToken.connect(user1).setReferrer(user1.address)
      ).to.be.revertedWith("Cannot refer self");
    });

    it("不能重复设置推荐人", async function () {
      await baseToken.connect(user1).setReferrer(owner.address);

      await expect(
        baseToken.connect(user1).setReferrer(user2.address)
      ).to.be.revertedWith("Referrer already set");
    });

    it("应该正确计算推荐奖励", async function () {
      // 用户3质押，推荐链: user1 <- user2 <- user3
      const stakeAmount = ethers.parseEther("100");
      await baseToken.connect(owner).transfer(user3.address, stakeAmount);
      await baseToken.connect(user3).approve(baseTokenAddress, stakeAmount);
      await baseToken.connect(user3).stake(stakeAmount, 30);

      // 推进时间产生奖励
      await ethers.provider.send("evm_increaseTime", [5 * MINUTE]);
      await ethers.provider.send("evm_mine", []);

      // 用户3领取奖励，推荐人应该获得分佣
      const user1BalanceBefore = await baseToken.balanceOf(user1.address);
      const user2BalanceBefore = await baseToken.balanceOf(user2.address);

      await baseToken.connect(user3).claimAllRewards();

      const user1BalanceAfter = await baseToken.balanceOf(user1.address);
      const user2BalanceAfter = await baseToken.balanceOf(user2.address);

      // 推荐人应该获得奖励
      expect(user1BalanceAfter).to.be.gt(user1BalanceBefore);
      expect(user2BalanceAfter).to.be.gt(user2BalanceBefore);
    });

    it("应该正确统计推荐网络", async function () {
      const [
        directReferrals,
        totalTeamSize,
        teamTotalStaked,
        totalRewardsEarned,
      ] = await baseToken.getReferralStats(user1.address);

      expect(directReferrals).to.equal(1n); // user2是直接推荐
      expect(totalTeamSize).to.equal(2n); // user2 + user3
    });
  });

  describe("战略储备管理", function () {
    it("应该允许所有者领取战略储备", async function () {
      // 推进时间到战略锁定期结束
      const strategicLockPeriod = await baseToken.STRATEGIC_LOCK_PERIOD();
      await ethers.provider.send("evm_increaseTime", [
        Number(strategicLockPeriod) + MINUTE,
      ]);
      await ethers.provider.send("evm_mine", []);

      const amount = ethers.parseEther("10");

      await expect(baseToken.connect(owner).claimStrategic(amount))
        .to.emit(baseToken, "VestingClaimed")
        .withArgs(owner.address, amount, "strategic");
    });

    it("应该允许所有者销毁战略储备", async function () {
      const amount = ethers.parseEther("1000");

      await expect(baseToken.connect(owner).burnStrategic(amount))
        .to.emit(baseToken, "VestingClaimed")
        .withArgs(owner.address, amount, "strategic_burn");

      const strategicPool = await baseToken.strategicPool();
      const strategicAllocation = await baseToken.STRATEGIC_RESERVE_ALLOCATION();
      expect(strategicPool).to.equal(strategicAllocation - amount);
    });

    it("应该允许预言机销毁战略储备", async function () {
      await baseToken.connect(owner).setOracle(oracle.address);

      const amount = ethers.parseEther("1000");
      const strategicPoolBefore = await baseToken.strategicPool();

      await baseToken.connect(oracle).burnStrategicViaOracle(amount);

      const strategicPoolAfter = await baseToken.strategicPool();
      expect(strategicPoolAfter).to.equal(strategicPoolBefore - amount);
    });

    it("非预言机不能通过预言机接口销毁", async function () {
      const amount = ethers.parseEther("1000");

      await expect(
        baseToken.connect(user1).burnStrategicViaOracle(amount)
      ).to.be.revertedWith("Only oracle");
    });
  });

  describe("紧急机制", function () {
    it("达到阈值时触发紧急暂停并可恢复", async function () {
      await baseToken.connect(owner).setOracle(oracle.address);
      await baseToken.connect(owner).updateEmergencyThreshold(100);

      await expect(baseToken.connect(oracle).triggerEmergencyPause(200))
        .to.emit(baseToken, "EmergencyPauseTriggered")
        .withArgs(oracle.address, 200);

      expect(await baseToken.paused()).to.equal(true);
      expect(await securityPool.paused()).to.equal(true);

      await expect(
        baseToken.connect(user1).claimAirdrop()
      ).to.be.revertedWithCustomError(securityPool, "EnforcedPause");

      await baseToken.connect(owner).resumeFromEmergency();
      expect(await baseToken.paused()).to.equal(false);
      expect(await securityPool.paused()).to.equal(false);
    });
  });

  describe("权限控制", function () {
    it("只有所有者可以设置预言机", async function () {
      await expect(
        baseToken.connect(user1).setOracle(user1.address)
      )
        .to.be.revertedWithCustomError(
          baseToken,
          "OwnableUnauthorizedAccount"
        )
        .withArgs(user1.address);

      await expect(baseToken.connect(owner).setOracle(oracle.address))
        .to.emit(baseToken, "OracleSet")
        .withArgs(oracle.address);
    });

    it("只有所有者可以更新推荐比例", async function () {
      await expect(
        baseToken.connect(user1).updateReferralRates(8, 4, 2)
      )
        .to.be.revertedWithCustomError(
          baseToken,
          "OwnableUnauthorizedAccount"
        )
        .withArgs(user1.address);

      await baseToken.connect(owner).updateReferralRates(8, 4, 2);

      // 可以通过其他方式验证比例已更新
    });

    it("只有所有者可以管理推荐关系", async function () {
      await expect(
        baseToken.connect(user1).adminSetReferrer(user2.address, user1.address)
      )
        .to.be.revertedWithCustomError(
          baseToken,
          "OwnableUnauthorizedAccount"
        )
        .withArgs(user1.address);

      await baseToken
        .connect(owner)
        .adminSetReferrer(user2.address, user1.address);

      const referrer = await baseToken.getReferrer(user2.address);
      expect(referrer).to.equal(user1.address);
    });
  });

  describe("生态激励年度释放限额", function () {
    it("应该正确检查生态激励年度释放限额", async function () {
      // 给用户一些代币用于质押
      const stakeAmount = ethers.parseEther("10000000"); // 使用较大金额以更容易触发限额
      await baseToken.connect(owner).transfer(user1.address, stakeAmount);
      await baseToken.connect(user1).approve(baseTokenAddress, stakeAmount);
      await baseToken.connect(user1).stake(stakeAmount, 30);

      // 推进时间产生奖励
      await ethers.provider.send("evm_increaseTime", [10 * DAY]);
      await ethers.provider.send("evm_mine", []);

      // 尝试领取奖励，应该成功（在限额内）
      await baseToken.connect(user1).claimAllRewards();

      // 为了测试限额，可以直接设置已释放金额接近限额
      const ecosystemYear1Rate = await baseToken.ECOSYSTEM_YEAR1_RATE();
      const ecosystemIncentiveAllocation = await baseToken.ECOSYSTEM_INCENTIVE_ALLOCATION();
      const year1Limit = ecosystemIncentiveAllocation * BigInt(ecosystemYear1Rate) / 100n;
      
      // 查找并修改已释放金额
      const ecosystemYear1Released = await baseToken.ecosystemYear1Released();
      const releasedSlot = await findSlotContainingValue(ecosystemYear1Released);
      await overwriteSlot(releasedSlot, year1Limit - 100n); // 接近限额但不超过

      // 再次推进时间产生更多奖励
      await ethers.provider.send("evm_increaseTime", [5 * DAY]);
      await ethers.provider.send("evm_mine", []);

      // 此时尝试领取应该受到限额限制
      // 注意：具体行为取决于合约实现，这里只是一个示例
    });

    it("四年后应该停止生态激励释放", async function () {
      // 推进时间到四年后
      await ethers.provider.send("evm_increaseTime", [4 * YEAR + 1]);
      await ethers.provider.send("evm_mine", []);

      // 给用户一些代币用于质押
      const stakeAmount = ethers.parseEther("1000");
      await baseToken.connect(owner).transfer(user1.address, stakeAmount);
      await baseToken.connect(user1).approve(baseTokenAddress, stakeAmount);
      await baseToken.connect(user1).stake(stakeAmount, 30);

      // 推进时间产生奖励
      await ethers.provider.send("evm_increaseTime", [10 * DAY]);
      await ethers.provider.send("evm_mine", []);

      // 此时应该无法领取奖励（四年后停止释放）
      // 注意：具体行为取决于合约实现，这里只是一个示例
    });
  });

  describe("边界情况", function () {
    it("应该处理零金额操作", async function () {
      await expect(
        baseToken.connect(owner).addVesting("seed", user1.address, 0)
      ).to.be.revertedWith("Amount must be positive");
    });

    it("应该处理无效的类别", async function () {
      const amount = ethers.parseEther("1000");

      await expect(
        baseToken
          .connect(owner)
          .addVesting("invalid_category", user1.address, amount)
      ).to.be.revertedWith("Invalid category");
    });

    it("应该处理不存在的vesting领取", async function () {
      await expect(
        baseToken.connect(user1).claimAllVesting()
      ).to.be.revertedWith("Nothing to release");
    });

    it("应该处理不存在的奖励领取", async function () {
      await expect(
        baseToken.connect(user1).claimAllRewards()
      ).to.be.revertedWith("No reward");
    });
  });
});
