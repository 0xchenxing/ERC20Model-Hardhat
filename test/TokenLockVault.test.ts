import { expect } from "chai";
import { ethers } from "hardhat";
import { TokenLockVault, TestERC20 } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("TokenLockVault 综合测试", function () {
  let token1: TestERC20;
  let token2: TestERC20;
  let vault: TokenLockVault;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let operator: SignerWithAddress;
  
  // 释放模式枚举
  const ReleaseMode = {
    Daily: 0,
    Weekly: 1,
    Monthly: 2,
    Quarterly: 3,
    Yearly: 4
  };
  
  beforeEach(async function () {
    // 获取签名者
    [owner, user1, user2, operator] = await ethers.getSigners();
    
    // 部署测试代币
    const TestERC20Factory = await ethers.getContractFactory("TestERC20");
    token1 = await TestERC20Factory.deploy(
      "Test Token 1",
      "TTK1",
      ethers.parseUnits("1000000", 18)
    );
    await token1.waitForDeployment();
    
    token2 = await TestERC20Factory.deploy(
      "Test Token 2",
      "TTK2",
      ethers.parseUnits("1000000", 18)
    );
    await token2.waitForDeployment();
    
    // 部署TokenLockVault合约
    const TokenLockVaultFactory = await ethers.getContractFactory("TokenLockVault");
    vault = await TokenLockVaultFactory.deploy(owner.address);
    await vault.waitForDeployment();
    
    // 向用户转账并授权
    for (const user of [user1, user2, operator]) {
      await token1.transfer(user.address, ethers.parseUnits("1000", 18));
      await token1.connect(user).approve(await vault.getAddress(), ethers.parseUnits("1000", 18));
      
      await token2.transfer(user.address, ethers.parseUnits("1000", 18));
      await token2.connect(user).approve(await vault.getAddress(), ethers.parseUnits("1000", 18));
    }
    
    // 设置操作员
    await vault.setOperator(operator.address, true);
  });
  
  describe("基本功能测试", function () {
    it("应该正确创建锁仓", async function () {
      const lockAmount = ethers.parseUnits("100", 18);
      const releasePeriods = 30;
      
      // 创建锁仓
      const tx = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Daily,
        releasePeriods,
        ethers.toUtf8Bytes("每日释放测试")
      );
      
      const receipt = await tx.wait();
      const lockCreatedEvent = receipt?.logs.find(
        (log: any) => log.fragment && log.fragment.name === "LockCreated"
      );
      
      // 验证事件
      expect(lockCreatedEvent).to.exist;
      const lockId = (lockCreatedEvent as any)?.args?.lockId;
      expect(lockId).to.equal(0);
      
      // 验证锁仓记录
      const lock = await vault.locks(lockId);
      expect(await lock.token).to.equal(await token1.getAddress());
      expect(lock.totalAmount).to.equal(lockAmount);
      expect(lock.releasedAmount).to.equal(0);
      expect(lock.beneficiary).to.equal(user1.address);
      expect(lock.mode).to.equal(ReleaseMode.Daily);
      expect(lock.totalPeriods).to.equal(releasePeriods);
      expect(lock.isActive).to.be.true;
    });
    
    it("应该正确为第三方创建锁仓", async function () {
      const lockAmount = ethers.parseUnits("50", 18);
      const releasePeriods = 7;
      
      // 操作员为user2创建锁仓
      const tx = await vault.connect(operator).lockForOther(
        user2.address,
        await token2.getAddress(),
        lockAmount,
        ReleaseMode.Weekly,
        releasePeriods,
        ethers.toUtf8Bytes("第三方锁仓测试")
      );
      
      const receipt = await tx.wait();
      const lockCreatedEvent = receipt?.logs.find(
        (log: any) => log.fragment && log.fragment.name === "LockCreated"
      );
      
      const lockId = (lockCreatedEvent as any)?.args?.lockId;
      expect(lockId).to.equal(0);
      
      // 验证锁仓记录
      const lock = await vault.locks(lockId);
      expect(lock.beneficiary).to.equal(user2.address);
      expect(await lock.token).to.equal(await token2.getAddress());
      
      // 验证用户锁仓列表
      // 注意：由于TypeChain生成的类型可能不支持直接获取数组，我们使用getUserLocks函数
      const userLocks = await vault.getUserLocks(user2.address);
      expect(userLocks.length).to.be.at.least(1);
      // 验证第一个锁仓的信息
      expect(await userLocks[0].token).to.equal(await token2.getAddress());
      expect(userLocks[0].beneficiary).to.equal(user2.address);
      expect(userLocks[0].isActive).to.be.true;
    });
    
    it("应该正确释放代币", async function () {
      const lockAmount = ethers.parseUnits("100", 18);
      const releasePeriods = 10;
      
      // 创建锁仓
      const tx = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Daily,
        releasePeriods,
        ethers.toUtf8Bytes("释放测试")
      );
      
      const receipt = await tx.wait();
      const lockCreatedEvent = receipt?.logs.find(
        (log: any) => log.fragment && log.fragment.name === "LockCreated"
      );
      
     const lockId = (lockCreatedEvent as any)?.args?.lockId;
      
      // 初始余额
      const initialBalance = await token1.balanceOf(user1.address);
      
      // 时间前进1天
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);
      
      // 释放代币
      await vault.connect(user1).release(lockId);
      
      // 验证余额变化
      const newBalance = await token1.balanceOf(user1.address);
      const expectedReleaseAmount = lockAmount / BigInt(releasePeriods);
      expect(newBalance).to.equal(initialBalance + expectedReleaseAmount);
      
      // 验证锁仓记录更新
      const lock = await vault.locks(lockId);
      expect(lock.releasedAmount).to.equal(expectedReleaseAmount);
      expect(lock.releaseCount).to.equal(1);
    });
    
    it("应该支持批量释放代币", async function () {
      const lockAmount = ethers.parseUnits("100", 18);
      const releasePeriods = 10;
      
      // 创建两个锁仓
      const tx1 = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Daily,
        releasePeriods,
        ethers.toUtf8Bytes("批量释放测试1")
      );
      
      const tx2 = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Daily,
        releasePeriods,
        ethers.toUtf8Bytes("批量释放测试2")
      );
      
      const receipt1 = await tx1.wait();
      const receipt2 = await tx2.wait();
      
      const lockId1 = (receipt1?.logs.find((log: any) => log.fragment?.name === "LockCreated") as any)?.args?.lockId;
      const lockId2 = (receipt2?.logs.find((log: any) => log.fragment?.name === "LockCreated") as any)?.args?.lockId;
      
      // 初始余额
      const initialBalance = await token1.balanceOf(user1.address);
      
      // 时间前进1天
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);
      
      // 批量释放
      await vault.connect(user1).batchRelease([lockId1, lockId2]);
      
      // 验证余额变化
      const newBalance = await token1.balanceOf(user1.address);
      const expectedReleaseAmount = (lockAmount / BigInt(releasePeriods)) * BigInt(2);
      expect(newBalance).to.equal(initialBalance + expectedReleaseAmount);
    });

    it("应该支持一键释放所有可释放代币", async function () {
      const lockAmount = ethers.parseUnits("100", 18);
      const releasePeriods = 10;
      const numberOfLocks = 3;
      
      // 创建多个锁仓
      for (let i = 0; i < numberOfLocks; i++) {
        await vault.connect(user1).lockForSelf(
          await token1.getAddress(),
          lockAmount,
          ReleaseMode.Daily,
          releasePeriods,
          ethers.toUtf8Bytes(`一键释放测试${i + 1}`)
        );
      }
      
      // 初始余额
      const initialBalance = await token1.balanceOf(user1.address);
      
      // 时间前进1天
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);
      
      // 执行一键释放
      const tx = await vault.connect(user1).releaseAll();
      const receipt = await tx.wait();
      
      // 验证释放事件数量
      const releaseEvents = receipt?.logs.filter((log: any) => log.fragment?.name === "TokensReleased") as any[];
      expect(releaseEvents.length).to.equal(numberOfLocks);
      
      // 验证余额变化
      const newBalance = await token1.balanceOf(user1.address);
      const expectedReleaseAmount = (lockAmount / BigInt(releasePeriods)) * BigInt(numberOfLocks);
      expect(newBalance).to.equal(initialBalance + expectedReleaseAmount);
    });
  });
  
  describe("不同释放模式测试", function () {
    it("应该支持每日释放模式", async function () {
      const lockAmount = ethers.parseUnits("30", 18);
      const releasePeriods = 30;
      
      // 创建每日释放锁仓
      const tx = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Daily,
        releasePeriods,
        ethers.toUtf8Bytes("每日释放测试")
      );
      
      const receipt = await tx.wait();
      const lockId = (receipt?.logs.find((log: any) => log.fragment?.name === "LockCreated") as any)?.args?.lockId;
      
      // 时间前进1天
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);
      
      // 计算可释放金额
      const [releasableAmount] = await vault.getReleasableAmount(lockId);
      expect(releasableAmount).to.equal(lockAmount / BigInt(releasePeriods));
    });
    
    it("应该支持每周释放模式", async function () {
      const lockAmount = ethers.parseUnits("14", 18);
      const releasePeriods = 2;
      
      // 创建每周释放锁仓
      const tx = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Weekly,
        releasePeriods,
        ethers.toUtf8Bytes("每周释放测试")
      );
      
      const receipt = await tx.wait();
      const lockId = (receipt?.logs.find((log: any) => log.fragment?.name === "LockCreated") as any)?.args?.lockId;
      
      // 时间前进1周
      await ethers.provider.send("evm_increaseTime", [86400 * 7]);
      await ethers.provider.send("evm_mine", []);
      
      // 计算可释放金额
      const [releasableAmount] = await vault.getReleasableAmount(lockId);
      expect(releasableAmount).to.equal(lockAmount / BigInt(releasePeriods));
    });
    
    it("应该支持每月释放模式", async function () {
      const lockAmount = ethers.parseUnits("60", 18);
      const releasePeriods = 2;
      
      // 创建每月释放锁仓
      const tx = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Monthly,
        releasePeriods,
        ethers.toUtf8Bytes("每月释放测试")
      );
      
      const receipt = await tx.wait();
      const lockId = (receipt?.logs.find((log: any) => log.fragment?.name === "LockCreated") as any)?.args?.lockId;
      
      // 时间前进30天
      await ethers.provider.send("evm_increaseTime", [86400 * 30]);
      await ethers.provider.send("evm_mine", []);
      
      // 计算可释放金额
      const [releasableAmount] = await vault.getReleasableAmount(lockId);
      expect(releasableAmount).to.equal(lockAmount / BigInt(releasePeriods));
    });
  });
  
  describe("权限控制测试", function () {
    it("非操作员不能为他人创建锁仓", async function () {
      const lockAmount = ethers.parseUnits("10", 18);
      
      // user1不是操作员，尝试为user2创建锁仓应该失败
      await expect(
        vault.connect(user1).lockForOther(
          user2.address,
          await token1.getAddress(),
          lockAmount,
          ReleaseMode.Daily,
          10,
          ethers.toUtf8Bytes("权限测试")
        )
      ).to.be.revertedWith("Not operator");
    });
    
    it("只有所有者可以设置操作员", async function () {
      // user1不是所有者，尝试设置操作员应该失败
      await expect(
        vault.connect(user1).setOperator(user2.address, true)
      ).to.be.reverted;
      
      // 验证操作员状态未改变
      expect(await vault.operators(user2.address)).to.be.false;
    });
    
    it("只有受益人可以释放代币", async function () {
      const lockAmount = ethers.parseUnits("10", 18);
      
      // 创建锁仓，受益人为user1
      const tx = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Daily,
        10,
        ethers.toUtf8Bytes("释放权限测试")
      );
      
      const receipt = await tx.wait();
      const lockId = (receipt?.logs.find((log: any) => log.fragment?.name === "LockCreated") as any)?.args?.lockId;
      
      // 时间前进1天
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);
      
      // user2不是受益人，尝试释放代币应该失败
      await expect(
        vault.connect(user2).release(lockId)
      ).to.be.revertedWith("Not beneficiary");
    });
  });
  
  describe("边界条件测试", function () {
    it("应该正确处理最后一期释放", async function () {
      const lockAmount = ethers.parseUnits("101", 18); // 使用101以便有余数
      const releasePeriods = 2;
      
      // 创建锁仓
      const tx = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Daily,
        releasePeriods,
        ethers.toUtf8Bytes("最后一期释放测试")
      );
      
      const receipt = await tx.wait();
      const lockId = (receipt?.logs.find((log: any) => log.fragment?.name === "LockCreated") as any)?.args?.lockId;
      
      // 初始余额
      const initialBalance = await token1.balanceOf(user1.address);
      
      // 时间前进1天
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);
      
      // 释放第一期
      await vault.connect(user1).release(lockId);
      const balanceAfterFirstRelease = await token1.balanceOf(user1.address);
      
      // 时间前进1天
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);
      
      // 释放最后一期
      await vault.connect(user1).release(lockId);
      const finalBalance = await token1.balanceOf(user1.address);
      
      // 总释放金额应该等于锁仓金额
      expect(finalBalance - initialBalance).to.equal(lockAmount);
      
      // 锁仓应该变为非活跃
      const lock = await vault.locks(lockId);
      expect(lock.isActive).to.be.false;
    });
    
    it("应该拒绝零金额锁仓", async function () {
      await expect(
        vault.connect(user1).lockForSelf(
          await token1.getAddress(),
          0,
          ReleaseMode.Daily,
          10,
          ethers.toUtf8Bytes("零金额测试")
        )
      ).to.be.revertedWith("Amount must be positive");
    });
    
    it("应该拒绝零期数锁仓", async function () {
      await expect(
        vault.connect(user1).lockForSelf(
          await token1.getAddress(),
          ethers.parseUnits("10", 18),
          ReleaseMode.Daily,
          0,
          ethers.toUtf8Bytes("零期数测试")
        )
      ).to.be.revertedWith("Total periods must be positive");
    });
    
    it("应该拒绝无效受益人地址", async function () {
      await expect(
        vault.connect(operator).lockForOther(
          ethers.ZeroAddress,
          await token1.getAddress(),
          ethers.parseUnits("10", 18),
          ReleaseMode.Daily,
          10,
          ethers.toUtf8Bytes("无效受益人测试")
        )
      ).to.be.revertedWith("Invalid beneficiary");
    });
    
    it("应该拒绝无效代币地址", async function () {
      await expect(
        vault.connect(user1).lockForSelf(
          ethers.ZeroAddress,
          ethers.parseUnits("10", 18),
          ReleaseMode.Daily,
          10,
          ethers.toUtf8Bytes("无效代币测试")
        )
      ).to.be.revertedWith("Invalid token address");
    });
  });
  
  describe("查询功能测试", function () {
    it("应该正确获取用户锁仓列表", async function() {
      const lockAmount = ethers.parseUnits("10", 18);
      
      // 创建三个锁仓
      await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Daily,
        10,
        ethers.toUtf8Bytes("查询测试1")
      );
      
      await vault.connect(user1).lockForSelf(
        await token2.getAddress(),
        lockAmount,
        ReleaseMode.Daily,
        10,
        ethers.toUtf8Bytes("查询测试2")
      );
      
      await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Weekly,
        5,
        ethers.toUtf8Bytes("查询测试3")
      );
      
      // 使用合约提供的getUserLocks函数获取用户锁仓列表
      const userLockRecords = await vault.getUserLocks(user1.address);
      
      // 验证用户有三个锁仓
      expect(userLockRecords.length).to.equal(3);
      
      // 验证锁仓信息
      for (const lockRecord of userLockRecords) {
        expect(lockRecord.isActive).to.be.true;
        expect(lockRecord.beneficiary).to.equal(user1.address);
      }
    });
    
    it("应该正确获取锁仓信息", async function() {
      const lockAmount = ethers.parseUnits("10", 18);
      
      // 创建锁仓
      const tx = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount,
        ReleaseMode.Daily,
        10,
        ethers.toUtf8Bytes("锁仓信息测试")
      );
      
      const receipt = await tx.wait();
      const lockId = (receipt?.logs.find((log: any) => log.fragment?.name === "LockCreated") as any)?.args?.lockId;
      
      // 获取锁仓信息
      const [beneficiary, totalAmount, releasedAmount, startTime, releaseCount, mode, totalPeriods, description, isActive, nextReleaseTime] = await vault.getLockInfo(lockId);
      expect(beneficiary).to.equal(user1.address);
      expect(totalAmount).to.equal(lockAmount);
      expect(releasedAmount).to.equal(0);
      expect(mode).to.equal(ReleaseMode.Daily);
      expect(totalPeriods).to.equal(10);
      expect(isActive).to.be.true;
      expect(ethers.toUtf8String(description)).to.equal("锁仓信息测试");
    });
    
    it("应该正确获取用户锁仓统计信息", async function() {
      const lockAmount1 = ethers.parseUnits("10", 18);
      const lockAmount2 = ethers.parseUnits("20", 18);
      
      // 创建两个锁仓
      const tx1 = await vault.connect(user1).lockForSelf(
        await token1.getAddress(),
        lockAmount1,
        ReleaseMode.Daily,
        10,
        ethers.toUtf8Bytes("统计测试1")
      );
      
      await vault.connect(user1).lockForSelf(
        await token2.getAddress(),
        lockAmount2,
        ReleaseMode.Daily,
        10,
        ethers.toUtf8Bytes("统计测试2")
      );
      
      // 获取第一个锁仓的ID
      const receipt1 = await tx1.wait();
      const lockId1 = (receipt1?.logs.find((log: any) => log.fragment?.name === "LockCreated") as any)?.args?.lockId;
      
      // 时间前进1天
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine", []);
      
      // 释放第一个锁仓的一期
      await vault.connect(user1).release(lockId1);
      
      // 获取用户锁仓统计
      const [totalLocked, totalReleased, activeLocks] = await vault.getUserLockStats(user1.address);
      expect(totalLocked).to.equal(lockAmount1 + lockAmount2);
      expect(totalReleased).to.equal(lockAmount1 / BigInt(10));
      expect(activeLocks).to.equal(2);
    });
  });
});
