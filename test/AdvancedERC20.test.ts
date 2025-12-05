import { expect } from "chai";
import { ethers } from "hardhat";
import { TestToken } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("AdvancedERC20", function () {
  let testToken: TestToken;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;
  let addr3: SignerWithAddress;
  let feeRecipient: SignerWithAddress;

  beforeEach(async function () {
    // 获取签名者账户
    [owner, addr1, addr2, addr3, feeRecipient] = await ethers.getSigners();

    // 部署测试合约
    const TestToken = await ethers.getContractFactory("TestToken");
    testToken = await TestToken.deploy(
      "Test Token", 
      "TEST", 
      ethers.parseEther("1000"), // initialSupply
      100, // initialTransferFee (1%)
      feeRecipient.address, // initialFeeRecipient
      owner.address // initialOwner
    );

    await testToken.waitForDeployment();
  });

  describe("Deployment", function () {
    it("应该设置正确的名称和符号", async function () {
      expect(await testToken.name()).to.equal("Test Token");
      expect(await testToken.symbol()).to.equal("TEST");
    });

    it("应该正确设置初始供应量", async function () {
      expect(await testToken.totalSupply()).to.equal(ethers.parseEther("1000"));
      expect(await testToken.balanceOf(owner.address)).to.equal(ethers.parseEther("1000"));
    });

    it("应该正确设置初始手续费配置", async function () {
      expect(await testToken.transferFee()).to.equal(100);
      expect(await testToken.feeRecipient()).to.equal(feeRecipient.address);
      expect(await testToken.feeEnabled()).to.equal(true);
    });

    it("应该将所有者和手续费接收者设为免手续费账户", async function () {
      expect(await testToken.feeExempt(owner.address)).to.equal(true);
      expect(await testToken.feeExempt(feeRecipient.address)).to.equal(true);
    });
  });

  describe("Transfer Fee", function () {
    it("应该对普通转账收取手续费", async function () {
      const amount = ethers.parseEther("100");
      const fee = (amount * 100n) / 10000n; // 1%
      const netAmount = amount - fee;

      // 先给addr1转账，确保它有足够的代币
      await testToken.transfer(addr1.address, ethers.parseEther("200"));
      
      // 打印转账前的余额
      console.log("转账前 addr1 余额:", ethers.formatEther(await testToken.balanceOf(addr1.address)));
      console.log("转账前 addr2 余额:", ethers.formatEther(await testToken.balanceOf(addr2.address)));
      console.log("转账前 feeRecipient 余额:", ethers.formatEther(await testToken.balanceOf(feeRecipient.address)));
      
      // 然后用addr1向addr2转账，测试手续费
      await testToken.connect(addr1).transfer(addr2.address, amount);
      
      // 打印转账后的余额
      console.log("转账后 addr1 余额:", ethers.formatEther(await testToken.balanceOf(addr1.address)));
      console.log("转账后 addr2 余额:", ethers.formatEther(await testToken.balanceOf(addr2.address)));
      console.log("转账后 feeRecipient 余额:", ethers.formatEther(await testToken.balanceOf(feeRecipient.address)));
      
      // 打印预期值
      const expectedAddr1Balance = ethers.parseEther("200") - amount;
      console.log("预期 addr1 余额:", ethers.formatEther(expectedAddr1Balance));
      console.log("预期 addr2 余额:", ethers.formatEther(netAmount));
      console.log("预期 feeRecipient 余额:", ethers.formatEther(fee));
      
      expect(await testToken.balanceOf(addr1.address)).to.equal(expectedAddr1Balance);
      expect(await testToken.balanceOf(addr2.address)).to.equal(netAmount);
      expect(await testToken.balanceOf(feeRecipient.address)).to.equal(fee);
    });

    it("应该不对免手续费账户收取手续费", async function () {
      const amount = ethers.parseEther("100");
      
      // 将addr1设为免手续费账户
      await testToken.setFeeExempt(addr1.address, true);
      
      await testToken.transfer(addr1.address, amount);

      expect(await testToken.balanceOf(owner.address)).to.equal(ethers.parseEther("900"));
      expect(await testToken.balanceOf(addr1.address)).to.equal(amount);
      expect(await testToken.balanceOf(feeRecipient.address)).to.equal(0);
    });

    it("应该可以更新手续费率", async function () {
      const newFee = 200; // 2%
      await testToken.setTransferFee(newFee);
      expect(await testToken.transferFee()).to.equal(newFee);
    });

    it("应该可以禁用手续费", async function () {
      await testToken.setFeeEnabled(false);
      expect(await testToken.feeEnabled()).to.equal(false);

      const amount = ethers.parseEther("100");
      await testToken.transfer(addr1.address, amount);

      expect(await testToken.balanceOf(addr1.address)).to.equal(amount);
      expect(await testToken.balanceOf(feeRecipient.address)).to.equal(0);
    });
  });

  describe("Referral System", function () {
    it("应该能建立推荐关系", async function () {
      const amount = ethers.parseEther("10");
      
      // addr1向addr2转账，建立推荐关系
      await testToken.transfer(addr1.address, ethers.parseEther("100"));
      await testToken.connect(addr1).transfer(addr2.address, amount);

      expect(await testToken.getReferrer(addr2.address)).to.equal(addr1.address);
      expect(await testToken.getReferralCount(addr1.address)).to.equal(1);
    });

    it("不应该允许自推荐", async function () {
      // 直接向某地址转账不应该建立自推荐关系
      await testToken.transfer(addr1.address, ethers.parseEther("100"));
      
      // 转账给自己不应该建立推荐关系
      await testToken.connect(addr1).transfer(addr1.address, ethers.parseEther("10"));
      
      expect(await testToken.getReferrer(addr1.address)).to.equal(ethers.ZeroAddress);
    });

    it("应该能获取推荐链", async function () {
      const amount = ethers.parseEther("10");
      
      // 先给所有地址转账，确保有足够的代币
      await testToken.transfer(addr1.address, ethers.parseEther("200"));
      await testToken.transfer(addr2.address, ethers.parseEther("100"));
      
      // 建立推荐链: addr1 -> addr2 -> addr3
      await testToken.connect(addr1).transfer(addr2.address, amount);
      await testToken.connect(addr2).transfer(addr3.address, amount);

      const referralChain = await testToken.getReferralChain(addr3.address, 0);
      expect(referralChain.length).to.equal(2);
      expect(referralChain[0]).to.equal(addr2.address);
      expect(referralChain[1]).to.equal(addr1.address);
    });

    it("应该可以禁用推荐系统", async function () {
      await testToken.setReferralEnabled(false);
      expect(await testToken.referralEnabled()).to.equal(false);

      const amount = ethers.parseEther("10");
      await testToken.transfer(addr1.address, ethers.parseEther("100"));
      await testToken.connect(addr1).transfer(addr2.address, amount);

      expect(await testToken.getReferrer(addr2.address)).to.equal(ethers.ZeroAddress);
    });
  });

  describe("Burning", function () {
    it("应该能够销毁代币", async function () {
      const burnAmount = ethers.parseEther("100");
      await testToken.burn(burnAmount);

      expect(await testToken.totalSupply()).to.equal(ethers.parseEther("900"));
      expect(await testToken.totalBurned()).to.equal(burnAmount);
    });

    it("应该可以通过转账到合约地址来销毁代币", async function () {
      const burnAmount = ethers.parseEther("100");
      await testToken.transfer(testToken.getAddress(), burnAmount);

      expect(await testToken.totalSupply()).to.equal(ethers.parseEther("900"));
      expect(await testToken.totalBurned()).to.equal(burnAmount);
    });

    it("应该可以禁用销毁功能", async function () {
      await testToken.setBurnEnabled(false);
      expect(await testToken.burnEnabled()).to.equal(false);

      await expect(testToken.burn(ethers.parseEther("100")))
        .to.be.revertedWith("Burn disabled");
    });
  });

  describe("Configuration", function () {
    it("应该能获取所有配置信息", async function () {
      const config = await testToken.getConfig();

      expect(config.currentTransferFee).to.equal(100);
      expect(config.currentFeeRecipient).to.equal(feeRecipient.address);
      expect(config.isFeeEnabled).to.equal(true);
      expect(config.isReferralEnabled).to.equal(true);
      expect(config.minReferralTransferAmount_).to.equal(0);
      expect(config.isBurnEnabled).to.equal(true);
      expect(config.totalSupply_).to.equal(ethers.parseEther("1000"));
      expect(config.totalBurned_).to.equal(0);
    });
  });

  describe("Additional Fee Tests", function () {
    it("应该正确计算转账手续费", async function () {
      const amount = ethers.parseEther("100");
      const expectedFee = (amount * 100n) / 10000n;
      
      const calculatedFee = await testToken.calculateTransferFee(amount);
      expect(calculatedFee).to.equal(expectedFee);
    });

    it("应该正确获取扣除手续费后的转账金额", async function () {
      const amount = ethers.parseEther("100");
      const expectedNetAmount = amount - (amount * 100n) / 10000n;
      
      const netAmount = await testToken.getTransferAmount(amount);
      expect(netAmount).to.equal(expectedNetAmount);
    });

    it("应该可以更新手续费接收地址", async function () {
      const newFeeRecipient = addr3.address;
      await testToken.setFeeRecipient(newFeeRecipient);
      
      expect(await testToken.feeRecipient()).to.equal(newFeeRecipient);
    });

    it("应该可以设置免手续费状态", async function () {
      // 将addr1设为免手续费账户
      await testToken.setFeeExempt(addr1.address, true);
      expect(await testToken.feeExempt(addr1.address)).to.equal(true);
      
      // 取消addr1的免手续费状态
      await testToken.setFeeExempt(addr1.address, false);
      expect(await testToken.feeExempt(addr1.address)).to.equal(false);
    });

    it("应该设置最大10%的手续费率", async function () {
      // 尝试设置超过10%的手续费，应该失败
      await expect(testToken.setTransferFee(1001)).to.be.revertedWith("Fee too high");
      
      // 设置10%的手续费，应该成功
      await testToken.setTransferFee(1000);
      expect(await testToken.transferFee()).to.equal(1000);
    });
  });

  describe("Additional Referral Tests", function () {
    it("应该可以设置推荐关系的最低转账金额", async function () {
      // 给addr1转账足够的代币
      await testToken.transfer(addr1.address, ethers.parseEther("200"));
      
      // 设置最低推荐转账金额为50 ETH
      await testToken.setMinReferralTransferAmount(ethers.parseEther("50"));
      
      // 转账51 ETH，扣除1%手续费后为50.49 ETH，大于50 ETH，应该建立推荐关系
      await testToken.connect(addr1).transfer(addr2.address, ethers.parseEther("51"));
      
      expect(await testToken.getReferrer(addr2.address)).to.equal(addr1.address);
      expect(await testToken.getReferralCount(addr1.address)).to.equal(1);
    });
  });

  describe("Additional Burning Tests", function () {
    it("应该可以使用burnFrom函数销毁代币", async function () {
      const burnAmount = ethers.parseEther("50");
      
      // 给addr1转账，然后批准合约burnFrom
      await testToken.transfer(addr1.address, ethers.parseEther("100"));
      await testToken.connect(addr1).approve(owner.address, burnAmount);
      
      // 使用burnFrom销毁addr1的代币
      await testToken.connect(owner).burnFrom(addr1.address, burnAmount);
      
      expect(await testToken.balanceOf(addr1.address)).to.equal(ethers.parseEther("50"));
      expect(await testToken.totalBurned()).to.equal(burnAmount);
    });
  });

  describe("Edge Cases", function () {
        it("应该处理零金额转账", async function () {
          // 零金额转账不应该收取手续费，也不应该建立推荐关系
          await testToken.transfer(addr1.address, ethers.parseEther("100"));
          await testToken.connect(addr1).transfer(addr2.address, 0);
          
          expect(await testToken.getReferrer(addr2.address)).to.equal(ethers.ZeroAddress);
        });

    it("应该检测推荐链循环", async function () {
      // 注意：由于_referrer是内部映射且没有外部设置方法，我们无法直接创建循环
      // 这里测试推荐链查询的循环检测机制
      // 建立一个线性推荐链，确保循环检测不会误报
      const amount = ethers.parseEther("10");
      
      await testToken.transfer(addr1.address, ethers.parseEther("200"));
      await testToken.transfer(addr2.address, ethers.parseEther("100"));
      await testToken.transfer(addr3.address, ethers.parseEther("100"));
      
      await testToken.connect(addr1).transfer(addr2.address, amount);
      await testToken.connect(addr2).transfer(addr3.address, amount);
      
      // 正常推荐链，应该返回正确的推荐链
      const chain = await testToken.getReferralChain(addr3.address, 0);
      expect(chain.length).to.equal(2);
    });
  });
});