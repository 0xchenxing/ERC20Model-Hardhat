import { expect } from "chai";
import { ethers } from "hardhat";
import { Oracle } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("Oracle", function () {
  let oracle: Oracle;
  let admin: SignerWithAddress;
  let dataUploader: SignerWithAddress;
  let projectAuthorizedSubmitter: SignerWithAddress;
  let unauthorizedUser: SignerWithAddress;

  const PROJECT_ID = ethers.encodeBytes32String("test-project");
  const PROJECT_DESCRIPTION = "Test project description";
  const DATA_TTL = 3600;
  const CORE_DATA = ethers.toUtf8Bytes("test-core-data");
  const DATA_HASH = ethers.keccak256(ethers.toUtf8Bytes("test-data-hash"));

  beforeEach(async function () {
    [admin, dataUploader, projectAuthorizedSubmitter, unauthorizedUser] = await ethers.getSigners();

    const Oracle = await ethers.getContractFactory("Oracle");
    oracle = await Oracle.deploy(admin.address);
    await oracle.waitForDeployment();

    await oracle.connect(admin).grantRole(await oracle.DATA_UPLOADER_ROLE(), dataUploader.address);
  });

  describe("部署与角色", function () {
    it("应该正确部署并分配管理员角色", async function () {
      expect(await oracle.hasRole(await oracle.DEFAULT_ADMIN_ROLE(), admin.address)).to.be.true;
    });

    it("应该正确分配数据上传者角色", async function () {
      expect(await oracle.hasRole(await oracle.DATA_UPLOADER_ROLE(), dataUploader.address)).to.be.true;
    });

    it("管理员应该能够分配数据上传者角色", async function () {
      await oracle.connect(admin).grantRole(await oracle.DATA_UPLOADER_ROLE(), unauthorizedUser.address);
      expect(await oracle.hasRole(await oracle.DATA_UPLOADER_ROLE(), unauthorizedUser.address)).to.be.true;
    });

    it("管理员应该能够撤销数据上传者角色", async function () {
      await oracle.connect(admin).revokeRole(await oracle.DATA_UPLOADER_ROLE(), dataUploader.address);
      expect(await oracle.hasRole(await oracle.DATA_UPLOADER_ROLE(), dataUploader.address)).to.be.false;
    });
  });

  describe("项目注册", function () {
    it("应该允许管理员注册新项目", async function () {
      await expect(
        oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL)
      ).to.emit(oracle, "ProjectRegistered")
        .withArgs(PROJECT_ID, admin.address, PROJECT_DESCRIPTION);

      const projectConfig = await oracle.getProjectConfig(PROJECT_ID);
      expect(projectConfig.isActive).to.be.true;
      expect(projectConfig.dataTTL).to.equal(DATA_TTL);
    });

    it("应该允许数据上传者注册新项目", async function () {
      await expect(
        oracle.connect(dataUploader).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL)
      ).to.emit(oracle, "ProjectRegistered")
        .withArgs(PROJECT_ID, dataUploader.address, PROJECT_DESCRIPTION);
    });

    it("不应该允许未授权用户注册项目", async function () {
      await expect(
        oracle.connect(unauthorizedUser).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL)
      ).to.be.revertedWith("Not authorized");
    });

    it("不应该允许注册已存在的项目", async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);

      await expect(
        oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL)
      ).to.be.revertedWith("Project already exists");
    });

    it("不应该允许注册TTL为0的项目", async function () {
      await expect(
        oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, 0)
      ).to.be.revertedWith("Data TTL must be positive");
    });
  });

  describe("项目配置", function () {
    beforeEach(async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);
    });

    it("应该允许管理员更新项目配置", async function () {
      const newTTL = 7200;
      await oracle.connect(admin).updateProjectConfig(PROJECT_ID, newTTL);

      const projectConfig = await oracle.getProjectConfig(PROJECT_ID);
      expect(projectConfig.dataTTL).to.equal(newTTL);
    });

    it("应该允许数据上传者更新项目配置", async function () {
      const newTTL = 7200;
      await oracle.connect(dataUploader).updateProjectConfig(PROJECT_ID, newTTL);

      const projectConfig = await oracle.getProjectConfig(PROJECT_ID);
      expect(projectConfig.dataTTL).to.equal(newTTL);
    });

    it("应该允许项目授权提交者更新项目配置", async function () {
      await oracle.connect(admin).addAuthorizedSubmitter(PROJECT_ID, projectAuthorizedSubmitter.address);
      
      const newTTL = 7200;
      await oracle.connect(projectAuthorizedSubmitter).updateProjectConfig(PROJECT_ID, newTTL);

      const projectConfig = await oracle.getProjectConfig(PROJECT_ID);
      expect(projectConfig.dataTTL).to.equal(newTTL);
    });

    it("不应该允许未授权用户更新项目配置", async function () {
      await expect(
        oracle.connect(unauthorizedUser).updateProjectConfig(PROJECT_ID, 7200)
      ).to.be.revertedWith("Not authorized");
    });
  });

  describe("授权提交者管理", function () {
    beforeEach(async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);
    });

    it("应该允许管理员添加授权提交者", async function () {
      await oracle.connect(admin).addAuthorizedSubmitter(PROJECT_ID, projectAuthorizedSubmitter.address);
      expect(await oracle.isAuthorizedSubmitter(PROJECT_ID, projectAuthorizedSubmitter.address)).to.be.true;
    });

    it("应该允许数据上传者添加授权提交者", async function () {
      await oracle.connect(dataUploader).addAuthorizedSubmitter(PROJECT_ID, projectAuthorizedSubmitter.address);
      expect(await oracle.isAuthorizedSubmitter(PROJECT_ID, projectAuthorizedSubmitter.address)).to.be.true;
    });

    it("应该允许项目授权提交者添加其他授权提交者", async function () {
      await oracle.connect(admin).addAuthorizedSubmitter(PROJECT_ID, projectAuthorizedSubmitter.address);
      
      await oracle.connect(projectAuthorizedSubmitter).addAuthorizedSubmitter(PROJECT_ID, unauthorizedUser.address);
      
      expect(await oracle.isAuthorizedSubmitter(PROJECT_ID, unauthorizedUser.address)).to.be.true;
    });

    it("不应该允许未授权用户添加授权提交者", async function () {
      await expect(
        oracle.connect(unauthorizedUser).addAuthorizedSubmitter(PROJECT_ID, projectAuthorizedSubmitter.address)
      ).to.be.revertedWith("Not authorized");
    });

    it("不应该重复添加相同的授权提交者", async function () {
      await oracle.connect(admin).addAuthorizedSubmitter(PROJECT_ID, projectAuthorizedSubmitter.address);
      
      await expect(
        oracle.connect(admin).addAuthorizedSubmitter(PROJECT_ID, projectAuthorizedSubmitter.address)
      ).to.be.revertedWith("Submitter already authorized");
    });
  });

  describe("DID格式转换", function () {
    it("应该正确编码年月日到DID", async function () {
      const did = await oracle.encodeYearMonthDayToDid(2023, 10, 1);
      const expectedDid = ethers.encodeBytes32String("20231001");
      expect(did).to.equal(expectedDid);
    });

    it("应该正确解码DID到年月日", async function () {
      const did = ethers.encodeBytes32String("20231001");
      const [decodedYear, decodedMonth, decodedDay] = await oracle.decodeDidToYearMonthDay(did);
      expect(decodedYear).to.equal(2023);
      expect(decodedMonth).to.equal(10);
      expect(decodedDay).to.equal(1);
    });

    it("应该验证有效的DID格式", async function () {
      const validDid = ethers.encodeBytes32String("20231001");
      const invalidDidMonth = ethers.encodeBytes32String("20231301");
      const invalidDidDay = ethers.encodeBytes32String("20231032");
      const outOfRangeDid = ethers.encodeBytes32String("20231");

      expect(await oracle.isValidYearMonthDayDid(validDid)).to.be.true;
      expect(await oracle.isValidYearMonthDayDid(invalidDidMonth)).to.be.false;
      expect(await oracle.isValidYearMonthDayDid(invalidDidDay)).to.be.false;
      expect(await oracle.isValidYearMonthDayDid(outOfRangeDid)).to.be.false;
    });
  });

  describe("数据提交", function () {
    beforeEach(async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);
    });

    it("应该允许管理员提交数据", async function () {
      const did = ethers.encodeBytes32String("20231001");
      await expect(
        oracle.connect(admin).submitData(PROJECT_ID, did, CORE_DATA, DATA_HASH)
      ).to.emit(oracle, "DataSubmitted");
    });

    it("应该允许数据上传者提交数据", async function () {
      const did = ethers.encodeBytes32String("20231001");
      await expect(
        oracle.connect(dataUploader).submitData(PROJECT_ID, did, CORE_DATA, DATA_HASH)
      ).to.emit(oracle, "DataSubmitted");
    });

    it("应该允许授权提交者提交数据", async function () {
      await oracle.connect(admin).addAuthorizedSubmitter(PROJECT_ID, projectAuthorizedSubmitter.address);
      const did = ethers.encodeBytes32String("20231001");

      await expect(
        oracle.connect(projectAuthorizedSubmitter).submitData(PROJECT_ID, did, CORE_DATA, DATA_HASH)
      ).to.emit(oracle, "DataSubmitted");
    });

    it("不应该允许未授权用户提交数据", async function () {
      const did = ethers.encodeBytes32String("20231001");
      await expect(
        oracle.connect(unauthorizedUser).submitData(PROJECT_ID, did, CORE_DATA, DATA_HASH)
      ).to.be.revertedWith("Not authorized submitter");
    });

    it("不应该允许提交无效格式的DID", async function () {
      const invalidDid = ethers.encodeBytes32String("202310");
      await expect(
        oracle.connect(admin).submitData(PROJECT_ID, invalidDid, CORE_DATA, DATA_HASH)
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

      await expect(
        oracle.connect(admin).batchSubmitData(
          [PROJECT_ID, PROJECT_ID, PROJECT_ID],
          dataIds,
          coreDataArray,
          dataHashes
        )
      ).to.emit(oracle, "DataSubmitted");
    });
  });

  describe("数据查询", function () {
    beforeEach(async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);
      const did = ethers.encodeBytes32String("20231001");
      await oracle.connect(admin).submitData(PROJECT_ID, did, CORE_DATA, DATA_HASH);
    });

    it("应该允许查询数据详情", async function () {
      const did = ethers.encodeBytes32String("20231001");
      const data = await oracle.getData(PROJECT_ID, did);

      expect(data.pid).to.equal(PROJECT_ID);
      expect(data.did).to.equal(did);
      expect(ethers.toUtf8String(data.coreData)).to.equal(ethers.toUtf8String(CORE_DATA));
      expect(data.dataHash).to.equal(DATA_HASH);
      expect(data.submitter).to.equal(admin.address);
      expect(data.submitTime).to.be.greaterThan(0);
    });

    it("应该允许查询数据哈希", async function () {
      const did = ethers.encodeBytes32String("20231001");
      const dataHash = await oracle.getDataHash(PROJECT_ID, did);
      expect(dataHash).to.equal(DATA_HASH);
    });

    it("应该允许查询核心数据", async function () {
      const did = ethers.encodeBytes32String("20231001");
      const coreData = await oracle.getCoreData(PROJECT_ID, did);
      expect(ethers.toUtf8String(coreData)).to.equal(ethers.toUtf8String(CORE_DATA));
    });

    it("不应该允许查询不存在的数据", async function () {
      const nonExistentDid = ethers.encodeBytes32String("202301");
      await expect(
        oracle.getData(PROJECT_ID, nonExistentDid)
      ).to.be.revertedWith("Data not found");
    });
  });

  describe("最新数据查询", function () {
    beforeEach(async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);
    });

    it("应该返回项目的最新数据", async function () {
      const did1 = ethers.encodeBytes32String("20231001");
      const did2 = ethers.encodeBytes32String("20231101");
      const did3 = ethers.encodeBytes32String("20231201");

      const coreData1 = ethers.toUtf8Bytes("data-1");
      const coreData2 = ethers.toUtf8Bytes("data-2");
      const coreData3 = ethers.toUtf8Bytes("data-3");

      const hash1 = ethers.keccak256(ethers.toUtf8Bytes("hash-1"));
      const hash2 = ethers.keccak256(ethers.toUtf8Bytes("hash-2"));
      const hash3 = ethers.keccak256(ethers.toUtf8Bytes("hash-3"));

      await oracle.connect(admin).submitData(PROJECT_ID, did1, coreData1, hash1);
      await oracle.connect(admin).submitData(PROJECT_ID, did2, coreData2, hash2);
      await oracle.connect(admin).submitData(PROJECT_ID, did3, coreData3, hash3);

      const latestData = await oracle.getLatestData(PROJECT_ID);
      expect(latestData.did).to.equal(did3);
      expect(ethers.toUtf8String(latestData.coreData)).to.equal("data-3");
    });

    it("应该返回项目的最新数据ID", async function () {
      const did1 = ethers.encodeBytes32String("20231001");
      const did2 = ethers.encodeBytes32String("20231101");

      const coreData1 = ethers.toUtf8Bytes("data-1");
      const coreData2 = ethers.toUtf8Bytes("data-2");

      const hash1 = ethers.keccak256(ethers.toUtf8Bytes("hash-1"));
      const hash2 = ethers.keccak256(ethers.toUtf8Bytes("hash-2"));

      await oracle.connect(admin).submitData(PROJECT_ID, did1, coreData1, hash1);
      await oracle.connect(admin).submitData(PROJECT_ID, did2, coreData2, hash2);

      const latestDid = await oracle.getLatestDataId(PROJECT_ID);
      expect(latestDid).to.equal(did2);
    });

    it("不应该允许查询不存在项目的最新数据", async function () {
      const nonExistentProjectId = ethers.encodeBytes32String("non-existent");
      await expect(
        oracle.getLatestData(nonExistentProjectId)
      ).to.be.revertedWith("Project not found");
    });

    it("不应该允许查询没有数据的项目的最新数据", async function () {
      await oracle.connect(admin).registerProject(
        ethers.encodeBytes32String("empty-project"),
        "Empty project",
        DATA_TTL
      );

      const emptyProjectId = ethers.encodeBytes32String("empty-project");
      await expect(
        oracle.getLatestData(emptyProjectId)
      ).to.be.revertedWith("No data found");
    });
  });

  describe("数据ID列表查询", function () {
    beforeEach(async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);
    });

    it("应该返回项目的所有数据ID", async function () {
      const did1 = ethers.encodeBytes32String("20231001");
      const did2 = ethers.encodeBytes32String("20231101");
      const did3 = ethers.encodeBytes32String("20231201");

      await oracle.connect(admin).submitData(PROJECT_ID, did1, CORE_DATA, DATA_HASH);
      await oracle.connect(admin).submitData(PROJECT_ID, did2, CORE_DATA, DATA_HASH);
      await oracle.connect(admin).submitData(PROJECT_ID, did3, CORE_DATA, DATA_HASH);

      const dataIds = await oracle.getDataIds(PROJECT_ID);
      expect(dataIds.length).to.equal(3);
    });

    it("应该返回空数组当没有数据时", async function () {
      const dataIds = await oracle.getDataIds(PROJECT_ID);
      expect(dataIds.length).to.equal(0);
    });

    it("不应该允许查询不存在项目的数据ID", async function () {
      const nonExistentProjectId = ethers.encodeBytes32String("non-existent");
      await expect(
        oracle.getDataIds(nonExistentProjectId)
      ).to.be.revertedWith("Project not found");
    });
  });

  describe("模糊查询", function () {
    beforeEach(async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);
    });

    it("应该按前缀模糊查询匹配的数据ID", async function () {
      const did1 = ethers.encodeBytes32String("20231001");
      const did2 = ethers.encodeBytes32String("20231002");
      const did3 = ethers.encodeBytes32String("20231101");

      await oracle.connect(admin).submitData(PROJECT_ID, did1, CORE_DATA, DATA_HASH);
      await oracle.connect(admin).submitData(PROJECT_ID, did2, CORE_DATA, DATA_HASH);
      await oracle.connect(admin).submitData(PROJECT_ID, did3, CORE_DATA, DATA_HASH);

      const prefix = ethers.encodeBytes32String("20231");
      const matchingIds = await oracle.getDataIdsByPrefix(PROJECT_ID, prefix);
      expect(matchingIds.length).to.equal(3);
    });

    it("应该按完整DID精确匹配", async function () {
      const did = ethers.encodeBytes32String("20231001");
      await oracle.connect(admin).submitData(PROJECT_ID, did, CORE_DATA, DATA_HASH);

      const matchingIds = await oracle.getDataIdsByPrefix(PROJECT_ID, did);
      expect(matchingIds.length).to.equal(1);
      expect(matchingIds[0]).to.equal(did);
    });

    it("应该返回空数组当没有匹配的数据ID", async function () {
      const did = ethers.encodeBytes32String("20231001");
      await oracle.connect(admin).submitData(PROJECT_ID, did, CORE_DATA, DATA_HASH);

      const nonMatchingPrefix = ethers.encodeBytes32String("2024");
      const matchingIds = await oracle.getDataIdsByPrefix(PROJECT_ID, nonMatchingPrefix);
      expect(matchingIds.length).to.equal(0);
    });

    it("不应该允许查询不存在项目的模糊匹配", async function () {
      const nonExistentProjectId = ethers.encodeBytes32String("non-existent");
      const prefix = ethers.encodeBytes32String("2023");
      await expect(
        oracle.getDataIdsByPrefix(nonExistentProjectId, prefix)
      ).to.be.revertedWith("Project not found");
    });
  });

  describe("按年月查询", function () {
    beforeEach(async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);
    });

    it("应该按年月查询匹配的数据ID", async function () {
      const did1 = ethers.encodeBytes32String("20231001");
      const did2 = ethers.encodeBytes32String("20231015");
      const did3 = ethers.encodeBytes32String("20231101");

      await oracle.connect(admin).submitData(PROJECT_ID, did1, CORE_DATA, DATA_HASH);
      await oracle.connect(admin).submitData(PROJECT_ID, did2, CORE_DATA, DATA_HASH);
      await oracle.connect(admin).submitData(PROJECT_ID, did3, CORE_DATA, DATA_HASH);

      const matchingIds = await oracle.getDataIdsByYearMonth(PROJECT_ID, 2023, 10);
      expect(matchingIds.length).to.equal(2);
    });

    it("应该返回指定年月的最新数据", async function () {
      const coreData1 = ethers.toUtf8Bytes("early-data");
      const coreData2 = ethers.toUtf8Bytes("late-data");
      const hash1 = ethers.keccak256(ethers.toUtf8Bytes("hash-1"));
      const hash2 = ethers.keccak256(ethers.toUtf8Bytes("hash-2"));

      await oracle.connect(admin).submitData(PROJECT_ID, ethers.encodeBytes32String("20231001"), coreData1, hash1);
      await oracle.connect(admin).submitData(PROJECT_ID, ethers.encodeBytes32String("20231002"), coreData2, hash2);

      const latestData = await oracle.getLatestDataByYearMonth(PROJECT_ID, 2023, 10);
      expect(ethers.toUtf8String(latestData.coreData)).to.equal("late-data");
    });

    it("不应该允许查询无效年份的数据", async function () {
      await expect(
        oracle.getDataIdsByYearMonth(PROJECT_ID, 1999, 10)
      ).to.be.revertedWith("Invalid year");
      await expect(
        oracle.getDataIdsByYearMonth(PROJECT_ID, 2101, 10)
      ).to.be.revertedWith("Invalid year");
    });

    it("不应该允许查询无效月份的数据", async function () {
      await expect(
        oracle.getDataIdsByYearMonth(PROJECT_ID, 2023, 0)
      ).to.be.revertedWith("Invalid month");
      await expect(
        oracle.getDataIdsByYearMonth(PROJECT_ID, 2023, 13)
      ).to.be.revertedWith("Invalid month");
    });

    it("应该返回空数组当没有匹配的数据", async function () {
      const matchingIds = await oracle.getDataIdsByYearMonth(PROJECT_ID, 2023, 10);
      expect(matchingIds.length).to.equal(0);
    });

    it("应该返回错误当查询没有数据的年月", async function () {
      await expect(
        oracle.getLatestDataByYearMonth(PROJECT_ID, 2023, 10)
      ).to.be.revertedWith("No data found for this period");
    });
  });

  describe("项目查询", function () {
    beforeEach(async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);
    });

    it("应该允许管理员查询所有项目", async function () {
      const projects = await oracle.connect(admin).getProjectsByAddress(admin.address);
      expect(projects.length).to.be.greaterThan(0);
    });

    it("应该允许数据上传者查询所有项目", async function () {
      const projects = await oracle.connect(dataUploader).getProjectsByAddress(dataUploader.address);
      expect(projects.length).to.be.greaterThan(0);
    });

    it("应该返回空数组当没有找到项目", async function () {
      const projects = await oracle.connect(unauthorizedUser).getProjectsByAddress(unauthorizedUser.address);
      expect(projects.length).to.equal(0);
    });
  });

  describe("边界情况", function () {
    it("应该处理零地址授权提交者", async function () {
      await oracle.connect(admin).registerProject(PROJECT_ID, PROJECT_DESCRIPTION, DATA_TTL);

      await expect(
        oracle.connect(admin).addAuthorizedSubmitter(PROJECT_ID, ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid submitter address");
    });

    it("应该处理不存在的项目配置更新", async function () {
      const nonExistentProjectId = ethers.encodeBytes32String("non-existent");
      
      await expect(
        oracle.connect(admin).updateProjectConfig(nonExistentProjectId, 7200)
      ).to.be.revertedWith("Project not found");
    });

    it("应该处理不存在项目的授权提交者添加", async function () {
      const nonExistentProjectId = ethers.encodeBytes32String("non-existent");
      
      await expect(
        oracle.connect(admin).addAuthorizedSubmitter(nonExistentProjectId, projectAuthorizedSubmitter.address)
      ).to.be.revertedWith("Project not found");
    });

    it("应该处理不存在项目的授权检查", async function () {
      const nonExistentProjectId = ethers.encodeBytes32String("non-existent");
      
      await expect(
        oracle.isAuthorizedSubmitter(nonExistentProjectId, admin.address)
      ).to.be.revertedWith("Project not found");
    });
  });
});
