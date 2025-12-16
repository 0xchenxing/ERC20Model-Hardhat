import { expect } from "chai";
import { ethers } from "hardhat";
import { Oracle } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("Oracle", function () {
  let oracle: Oracle;
  let owner: SignerWithAddress;
  let projectOwner: SignerWithAddress;
  let authorizedSubmitter: SignerWithAddress;
  let unauthorizedUser: SignerWithAddress;

  // 测试用的常量
  const PROJECT_ID = ethers.encodeBytes32String("test-project");
  const PROJECT_DESCRIPTION = "Test project description";
  const DATA_TTL = 3600; // 1小时
  const DATA_ID_20231001 = ethers.encodeBytes32String("20231001"); // 使用年月日格式
  const CORE_DATA = ethers.toUtf8Bytes("test-core-data");
  // 使用简单的哈希值进行测试
  const DATA_HASH = ethers.keccak256(ethers.toUtf8Bytes("test-data-hash"));

  beforeEach(async function () {
    // 获取签名者账户
    [owner, projectOwner, authorizedSubmitter, unauthorizedUser] = await ethers.getSigners();

    // 部署Oracle合约
    const Oracle = await ethers.getContractFactory("Oracle");
    oracle = await Oracle.deploy(owner.address);
    await oracle.waitForDeployment();
  });

  describe("Deployment", function () {
    it("应该将初始所有者设置正确", async function () {
      expect(await oracle.owner()).to.equal(owner.address);
    });
  });

  describe("Project Management", function () {
    it("应该允许用户注册新项目", async function () {
      await expect(
        oracle.connect(projectOwner).registerProject(
          PROJECT_ID,
          PROJECT_DESCRIPTION,
          DATA_TTL
        )
      ).to.emit(oracle, "ProjectRegistered")
        .withArgs(PROJECT_ID, projectOwner.address, PROJECT_DESCRIPTION);

      // 验证项目配置
      const projectConfig = await oracle.getProjectConfig(PROJECT_ID);
      expect(projectConfig.owner).to.equal(projectOwner.address);
      expect(projectConfig.isActive).to.be.true;
      expect(projectConfig.dataTTL).to.equal(DATA_TTL);
    });

    it("不应该允许注册已存在的项目", async function () {
      // 先注册一次
      await oracle.connect(projectOwner).registerProject(
        PROJECT_ID,
        PROJECT_DESCRIPTION,
        DATA_TTL
      );

      // 再次注册应该失败
      await expect(
        oracle.connect(projectOwner).registerProject(
          PROJECT_ID,
          PROJECT_DESCRIPTION,
          DATA_TTL
        )
      ).to.be.revertedWith("Project already exists");
    });

    it("不应该允许注册TTL为0的项目", async function () {
      await expect(
        oracle.connect(projectOwner).registerProject(
          PROJECT_ID,
          PROJECT_DESCRIPTION,
          0
        )
      ).to.be.revertedWith("Data TTL must be positive");
    });

    it("应该允许项目所有者更新项目配置", async function () {
      // 注册项目
      await oracle.connect(projectOwner).registerProject(
        PROJECT_ID,
        PROJECT_DESCRIPTION,
        DATA_TTL
      );

      // 更新TTL
      const newTTL = 7200;
      await oracle.connect(projectOwner).updateProjectConfig(PROJECT_ID, newTTL);

      // 验证更新
      const projectConfig = await oracle.getProjectConfig(PROJECT_ID);
      expect(projectConfig.dataTTL).to.equal(newTTL);
    });

    it("不应该允许非项目所有者更新项目配置", async function () {
      // 注册项目
      await oracle.connect(projectOwner).registerProject(
        PROJECT_ID,
        PROJECT_DESCRIPTION,
        DATA_TTL
      );

      // 非项目所有者尝试更新应该失败
      await expect(
        oracle.connect(unauthorizedUser).updateProjectConfig(PROJECT_ID, 7200)
      ).to.be.revertedWith("Only project owner");
    });

    it("应该允许添加授权提交者", async function () {
      // 注册项目
      await oracle.connect(projectOwner).registerProject(
        PROJECT_ID,
        PROJECT_DESCRIPTION,
        DATA_TTL
      );

      // 添加授权提交者
      await oracle.connect(projectOwner).addAuthorizedSubmitter(PROJECT_ID, authorizedSubmitter.address);

      // 验证授权
      expect(await oracle.isAuthorizedSubmitter(PROJECT_ID, authorizedSubmitter.address)).to.be.true;
    });
  });

  describe("DID Formatting", function () {
    it("应该正确编码年月日到DID", async function () {
      const year = 2023;
      const month = 10;
      const day = 1;
      const did = await oracle.encodeYearMonthDayToDid(year, month, day);
      
      // 手动构造预期的DID
      const expectedDid = ethers.encodeBytes32String("20231001");
      expect(did).to.equal(expectedDid);
    });

    it("应该正确解码DID到年月日", async function () {
      const year = 2023;
      const month = 10;
      const day = 1;
      const did = ethers.encodeBytes32String("20231001");
      
      const [decodedYear, decodedMonth, decodedDay] = await oracle.decodeDidToYearMonthDay(did);
      expect(decodedYear).to.equal(year);
      expect(decodedMonth).to.equal(month);
      expect(decodedDay).to.equal(day);
    });

    it("应该验证有效的DID格式", async function () {
      const validDid = ethers.encodeBytes32String("20231001");
      const invalidDidMonth = ethers.encodeBytes32String("20231301"); // 无效的月份
      const invalidDidDay = ethers.encodeBytes32String("20231032"); // 无效的日期
      const outOfRangeDid = ethers.encodeBytes32String("20231"); // 长度不足

      expect(await oracle.isValidYearMonthDayDid(validDid)).to.be.true;
      expect(await oracle.isValidYearMonthDayDid(invalidDidMonth)).to.be.false;
      expect(await oracle.isValidYearMonthDayDid(invalidDidDay)).to.be.false;
      expect(await oracle.isValidYearMonthDayDid(outOfRangeDid)).to.be.false;
    });
  });

  describe("Data Submission", function () {
    beforeEach(async function () {
      // 注册项目
      await oracle.connect(projectOwner).registerProject(
        PROJECT_ID,
        PROJECT_DESCRIPTION,
        DATA_TTL
      );
    });

    it("应该允许项目所有者提交数据", async function () {
      // 执行交易并验证事件存在
      await expect(
        oracle.connect(projectOwner).submitData(
          PROJECT_ID,
          DATA_ID_20231001,
          CORE_DATA,
          DATA_HASH
        )
      ).to.emit(oracle, "DataSubmitted");
    });

    it("应该允许授权提交者提交数据", async function () {
      // 添加授权提交者
      await oracle.connect(projectOwner).addAuthorizedSubmitter(PROJECT_ID, authorizedSubmitter.address);

      // 执行交易并验证事件存在
      await expect(
        oracle.connect(authorizedSubmitter).submitData(
          PROJECT_ID,
          DATA_ID_20231001,
          CORE_DATA,
          DATA_HASH
        )
      ).to.emit(oracle, "DataSubmitted");
    });

    it("不应该允许未授权用户提交数据", async function () {
      await expect(
        oracle.connect(unauthorizedUser).submitData(
          PROJECT_ID,
          DATA_ID_20231001,
          CORE_DATA,
          DATA_HASH
        )
      ).to.be.revertedWith("Not authorized submitter");
    });

    it("不应该允许提交无效格式的DID", async function () {
      const invalidDid = ethers.encodeBytes32String("202310"); // 缺少日期部分

      await expect(
        oracle.connect(projectOwner).submitData(
          PROJECT_ID,
          invalidDid,
          CORE_DATA,
          DATA_HASH
        )
      ).to.be.reverted;
    });

    it("应该允许批量提交数据", async function () {
      const dataIds = [
        ethers.encodeBytes32String("20231001"),
        ethers.encodeBytes32String("20231101"),
        ethers.encodeBytes32String("20231201")
      ];
      const coreDataArray = [
        ethers.toUtf8Bytes("test-data-1"),
        ethers.toUtf8Bytes("test-data-2"),
        ethers.toUtf8Bytes("test-data-3")
      ];
      const dataHashes = [
        ethers.keccak256(ethers.toUtf8Bytes("hash-1")),
        ethers.keccak256(ethers.toUtf8Bytes("hash-2")),
        ethers.keccak256(ethers.toUtf8Bytes("hash-3"))
      ];

      // 批量提交数据
      await expect(
        oracle.connect(projectOwner).batchSubmitData(
          [PROJECT_ID, PROJECT_ID, PROJECT_ID],
          dataIds,
          coreDataArray,
          dataHashes
        )
      ).to.emit(oracle, "DataSubmitted");

      // 验证所有数据都已提交
      for (let i = 0; i < dataIds.length; i++) {
        const data = await oracle.getData(PROJECT_ID, dataIds[i]);
        expect(ethers.toUtf8String(data.coreData)).to.equal(ethers.toUtf8String(coreDataArray[i]));
        expect(data.dataHash).to.equal(dataHashes[i]);
      }
    });
  });

  describe("Data Query", function () {
    beforeEach(async function () {
      // 注册项目并提交数据
      await oracle.connect(projectOwner).registerProject(
        PROJECT_ID,
        PROJECT_DESCRIPTION,
        DATA_TTL
      );

      await oracle.connect(projectOwner).submitData(
        PROJECT_ID,
        DATA_ID_20231001,
        CORE_DATA,
        DATA_HASH
      );
    });

    it("应该允许查询数据详情", async function () {
      const data = await oracle.getData(PROJECT_ID, DATA_ID_20231001);

      expect(data.pid).to.equal(PROJECT_ID);
      expect(data.did).to.equal(DATA_ID_20231001);
      expect(ethers.toUtf8String(data.coreData)).to.equal(ethers.toUtf8String(CORE_DATA));
      expect(data.dataHash).to.equal(DATA_HASH);
      expect(data.submitter).to.equal(projectOwner.address);
      expect(data.submitTime).to.be.greaterThan(0);
    });

    it("应该允许单独查询数据哈希", async function () {
      const dataHash = await oracle.getDataHash(PROJECT_ID, DATA_ID_20231001);
      expect(dataHash).to.equal(DATA_HASH);
    });

    it("应该允许单独查询核心数据", async function () {
      const coreData = await oracle.getCoreData(PROJECT_ID, DATA_ID_20231001);
      expect(ethers.toUtf8String(coreData)).to.equal(ethers.toUtf8String(CORE_DATA));
    });

    it("不应该允许查询不存在的数据", async function () {
      const nonExistentDid = ethers.encodeBytes32String("202301");
      await expect(
        oracle.getData(PROJECT_ID, nonExistentDid)
      ).to.be.revertedWith("Data not found");
    });
  });
});