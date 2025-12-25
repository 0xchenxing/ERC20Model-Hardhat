// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOracle} from "../interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title 预言机实现合约
 * @notice 实现IOracle接口，接收链下数据上链，供业务合约读取数据
 */
contract Oracle is IOracle, Ownable {
    // ============ 构造函数 ============
    
    /**
     * @dev 构造函数
     * @param initialOwner 初始所有者地址
     */
    constructor(address initialOwner) Ownable(initialOwner) {
        // 构造函数逻辑
    }
    
    // ============ 存储 ============
    
    // 项目配置映射 (pid => ProjectConfig)
    mapping(bytes32 => ProjectConfig) private projectConfigs;
    
    // 项目是否存在映射
    mapping(bytes32 => bool) private projectExists;
    
    // 所有项目ID数组
    bytes32[] private allProjects;
    
    // 项目授权提交者映射 (pid => submitter => bool)
    mapping(bytes32 => mapping(address => bool)) private authorizedSubmitters;
    
    // 数据存储映射 (pid => did => OracleData)
    mapping(bytes32 => mapping(bytes32 => OracleData)) private oracleData;
    
    // 数据是否存在映射
    mapping(bytes32 => mapping(bytes32 => bool)) private dataExists;
    
    // 地址到项目的映射 (addr => projects array)
    mapping(address => bytes32[]) private addressToProjects;
    
    // 地址项目去重映射 (addr => pid => bool)
    mapping(address => mapping(bytes32 => bool)) private addressProjectExists;
    
    // ============ 辅助函数 ============
    
    /**
     * @dev 检查地址是否为授权提交者
     * @param pid 项目ID
     * @param submitter 提交者地址
     * @return 是否为授权提交者
     */
    function isAuthorizedSubmitter(
        bytes32 pid,
        address submitter
    ) public view override returns (bool) {
        require(projectExists[pid], "Project not found");
        return submitter == projectConfigs[pid].owner || authorizedSubmitters[pid][submitter] || submitter == owner();
    }
    
    /**
     * @dev 将年月日转换为标准的did格式
     * @param year 年份（如2023）
     * @param month 月份（1-12）
     * @param day 日期（1-31）
     * @return did 转换后的did（格式：年月日，如"20231001"表示2023年10月1日）
     */
    function encodeYearMonthDayToDid(uint16 year, uint8 month, uint8 day) external pure override returns (bytes32 did) {
        require(year >= 2000 && year <= 2100, "Invalid year range");
        require(month >= 1 && month <= 12, "Invalid month");
        require(day >= 1 && day <= 31, "Invalid day");
        
        // 直接构建ASCII字符
        bytes32 result = bytes32(0);
        
        // 年份的每一位数字
        result = bytes32(uint256(result) | (uint256(uint8((year / 1000) % 10 + 48)) << 248));
        result = bytes32(uint256(result) | (uint256(uint8((year / 100) % 10 + 48)) << 240));
        result = bytes32(uint256(result) | (uint256(uint8((year / 10) % 10 + 48)) << 232));
        result = bytes32(uint256(result) | (uint256(uint8(year % 10 + 48)) << 224));
        
        // 月份的每一位数字
        result = bytes32(uint256(result) | (uint256(uint8((month / 10) % 10 + 48)) << 216));
        result = bytes32(uint256(result) | (uint256(uint8(month % 10 + 48)) << 208));
        
        // 日期的每一位数字
        result = bytes32(uint256(result) | (uint256(uint8((day / 10) % 10 + 48)) << 200));
        result = bytes32(uint256(result) | (uint256(uint8(day % 10 + 48)) << 192));
        
        return result;
    }
    
    /**
     * @dev 从did中解析出年月日
     * @param did 数据ID（格式：年月日，如"20231001"表示2023年10月1日）
     * @return year 年份
     * @return month 月份
     * @return day 日期
     */
    function decodeDidToYearMonthDay(bytes32 did) public pure override returns (uint16 year, uint8 month, uint8 day) {
        // 提取前8个字符（年月日）
        bytes memory didBytes = abi.encodePacked(did);
        
        // 验证是否是有效的数字字符，并且只检查实际使用的字节（前8个）
        for (uint i = 0; i < 8; i++) {
            // 检查字节是否为数字字符
            uint8 char = uint8(didBytes[i]);
            require(char >= 48 && char <= 57, "Invalid character in DID");
        }
        
        year = uint16(
            ((uint8(didBytes[0]) - 48) * 1000) +
            ((uint8(didBytes[1]) - 48) * 100) +
            ((uint8(didBytes[2]) - 48) * 10) +
            (uint8(didBytes[3]) - 48)
        );
        
        month = uint8(
            ((uint8(didBytes[4]) - 48) * 10) +
            (uint8(didBytes[5]) - 48)
        );
        
        day = uint8(
            ((uint8(didBytes[6]) - 48) * 10) +
            (uint8(didBytes[7]) - 48)
        );
        
        return (year, month, day);
    }
    
    /**
     * @dev 验证did是否为有效的年月日格式
     * @param did 数据ID
     * @return isValid 是否为有效的年月日格式
     */
    function isValidYearMonthDayDid(bytes32 did) external pure override returns (bool isValid) {
        // 直接实现验证逻辑，避免使用this指针
        bytes memory didBytes = abi.encodePacked(did);
        
        // 验证是否是有效的数字字符
        for (uint i = 0; i < 8; i++) {
            uint8 char = uint8(didBytes[i]);
            if (char < 48 || char > 57) {
                return false;
            }
        }
        
        // 提取并验证年月日
        uint16 year = uint16(
            ((uint8(didBytes[0]) - 48) * 1000) +
            ((uint8(didBytes[1]) - 48) * 100) +
            ((uint8(didBytes[2]) - 48) * 10) +
            (uint8(didBytes[3]) - 48)
        );
        
        uint8 month = uint8(
            ((uint8(didBytes[4]) - 48) * 10) +
            (uint8(didBytes[5]) - 48)
        );
        
        uint8 day = uint8(
            ((uint8(didBytes[6]) - 48) * 10) +
            (uint8(didBytes[7]) - 48)
        );
        
        return year >= 2000 && year <= 2100 && month >= 1 && month <= 12 && day >= 1 && day <= 31;
    }
    
    // ============ 管理函数 ============
    
    /**
     * @dev 注册新项目
     * @param pid 项目ID
     * @param description 项目描述
     * @param dataTTL 数据有效期
     */
    function registerProject(
        bytes32 pid,
        string calldata description,
        uint256 dataTTL
    ) external override {
        require(!projectExists[pid], "Project already exists");
        require(dataTTL > 0, "Data TTL must be positive");
        
        ProjectConfig memory config = ProjectConfig({
            owner: msg.sender,
            isActive: true,
            description: bytes(description),
            authorizedSubmitters: new address[](0),
            dataTTL: dataTTL
        });
        
        projectConfigs[pid] = config;
        projectExists[pid] = true;
        allProjects.push(pid);
        
        // 将项目ID添加到所有者的项目列表中（如果不存在）
        if (!addressProjectExists[msg.sender][pid]) {
            addressToProjects[msg.sender].push(pid);
            addressProjectExists[msg.sender][pid] = true;
        }
        
        emit ProjectRegistered(pid, msg.sender, description);
    }
    
    /**
     * @dev 更新项目配置
     * @param pid 项目ID
     * @param dataTTL 数据有效期
     */
    function updateProjectConfig(
        bytes32 pid,
        uint256 dataTTL
    ) external override {
        require(projectExists[pid], "Project not found");
        require(msg.sender == projectConfigs[pid].owner, "Only project owner");
        require(dataTTL > 0, "Data TTL must be positive");
        
        projectConfigs[pid].dataTTL = dataTTL;
    }
    
    /**
     * @dev 添加授权提交者
     * @param pid 项目ID
     * @param submitter 提交者地址
     */
    function addAuthorizedSubmitter(
        bytes32 pid,
        address submitter
    ) external override {
        require(projectExists[pid], "Project not found");
        require(msg.sender == projectConfigs[pid].owner || msg.sender == owner(), "Only project owner");
        require(submitter != address(0), "Invalid submitter address");
        require(!authorizedSubmitters[pid][submitter], "Submitter already authorized");
        
        authorizedSubmitters[pid][submitter] = true;
        projectConfigs[pid].authorizedSubmitters.push(submitter);
        
        // 将项目ID添加到提交者的项目列表中（如果不存在）
        if (!addressProjectExists[submitter][pid]) {
            addressToProjects[submitter].push(pid);
            addressProjectExists[submitter][pid] = true;
        }
    }
    
    // ============ 数据提交函数 ============
    
    /**
     * @dev 提交数据（仅限项目方或授权提交者）
     * @param pid 项目ID
     * @param did 数据ID（格式：年月日，如"20231001"表示2023年10月1日）
     * @param coreData 核心数据
     * @param dataHash 总数据哈希
     */
    function submitData(
        bytes32 pid,
        bytes32 did,
        bytes calldata coreData,
        bytes32 dataHash
    ) external override {
        // 调用内部函数处理数据提交逻辑
        _submitData(pid, did, coreData, dataHash);
    }
    
    /**
     * @dev 批量提交数据（仅限项目方或授权提交者）
     * @param pids 项目ID数组
     * @param dids 数据ID数组（格式：年月日，如"20231001"表示2023年10月1日）
     * @param coreDataArray 核心数据数组
     * @param dataHashes 数据哈希数组
     */
    function batchSubmitData(
        bytes32[] calldata pids,
        bytes32[] calldata dids,
        bytes[] calldata coreDataArray,
        bytes32[] calldata dataHashes
    ) external override {
        require(pids.length == dids.length, "Array length mismatch");
        require(pids.length == coreDataArray.length, "Array length mismatch");
        require(pids.length == dataHashes.length, "Array length mismatch");
        
        for (uint256 i = 0; i < pids.length; i++) {
            // 直接调用内部实现逻辑，避免循环依赖
            _submitData(pids[i], dids[i], coreDataArray[i], dataHashes[i]);
        }
    }
    
    /**
     * @dev 内部数据提交函数，用于处理数据提交逻辑
     */
    function _submitData(
        bytes32 pid,
        bytes32 did,
        bytes calldata coreData,
        bytes32 dataHash
    ) internal {
        require(projectExists[pid], "Project not found");
        require(projectConfigs[pid].isActive, "Project not active");
        require(isAuthorizedSubmitter(pid, msg.sender), "Not authorized submitter");
        
        // 手动验证did格式
        (uint16 year, uint8 month, uint8 day) = decodeDidToYearMonthDay(did);
        require(year >= 2000 && year <= 2100 && month >= 1 && month <= 12 && day >= 1 && day <= 31, "Invalid did format");
        
        OracleData memory data = OracleData({
            pid: pid,
            did: did,
            coreData: coreData,
            dataHash: dataHash,
            submitter: msg.sender,
            submitTime: block.timestamp
        });
        
        oracleData[pid][did] = data;
        dataExists[pid][did] = true;
        
        emit DataSubmitted(pid, did, msg.sender, block.timestamp);
    }
    
    // ============ 查询函数 ============
    
    /**
     * @dev 获取数据详情
     * @param pid 项目ID
     * @param did 数据ID（格式：年月日，如"20231001"表示2023年10月1日）
     * @return data 数据详情
     */
    function getData(
        bytes32 pid,
        bytes32 did
    ) external view override returns (OracleData memory data) {
        require(dataExists[pid][did], "Data not found");
        require(projectConfigs[pid].isActive, "Project not active");
        
        // 检查数据是否过期
        OracleData memory oracleDataItem = oracleData[pid][did];
        require(block.timestamp - oracleDataItem.submitTime <= projectConfigs[pid].dataTTL, "Data expired");
        
        return oracleDataItem;
    }
    
    /**
     * @dev 获取项目配置
     * @param pid 项目ID
     * @return config 项目配置
     */
    function getProjectConfig(
        bytes32 pid
    ) external view override returns (ProjectConfig memory config) {
        require(projectExists[pid], "Project not found");
        return projectConfigs[pid];
    }
    
    /**
     * @dev 获取数据哈希
     * @param pid 项目ID
     * @param did 数据ID（格式：年月日，如"20231001"表示2023年10月1日）
     * @return dataHash 数据哈希
     */
    function getDataHash(
        bytes32 pid,
        bytes32 did
    ) external view override returns (bytes32 dataHash) {
        require(dataExists[pid][did], "Data not found");
        require(projectConfigs[pid].isActive, "Project not active");
        
        OracleData memory oracleDataItem = oracleData[pid][did];
        require(block.timestamp - oracleDataItem.submitTime <= projectConfigs[pid].dataTTL, "Data expired");
        
        return oracleDataItem.dataHash;
    }
    
    /**
     * @dev 获取核心数据
     * @param pid 项目ID
     * @param did 数据ID（格式：年月日，如"20231001"表示2023年10月1日）
     * @return coreData 核心数据
     */
    function getCoreData(
        bytes32 pid,
        bytes32 did
    ) external view override returns (bytes memory coreData) {
        require(dataExists[pid][did], "Data not found");
        require(projectConfigs[pid].isActive, "Project not active");
        
        OracleData memory oracleDataItem = oracleData[pid][did];
        require(block.timestamp - oracleDataItem.submitTime <= projectConfigs[pid].dataTTL, "Data expired");
        
        return oracleDataItem.coreData;
    }
    
    /**
     * @dev 获取项目所有者
     * @param pid 项目ID
     * @return owner 项目所有者地址
     */
    function getProjectOwner(
        bytes32 pid
    ) external view override returns (address owner) {
        require(projectExists[pid], "Project not found");
        return projectConfigs[pid].owner;
    }
    
    /**
     * @dev 通过地址查询对应项目
     * @param addr 查询地址
     * @return projects 该地址作为所有者或授权提交者的所有项目ID
     */
    function getProjectsByAddress(
        address addr
    ) external view override returns (bytes32[] memory projects) {
        require(addr != address(0), "Invalid address");
        
        // 如果是合约拥有者，返回所有项目
        if (addr == owner()) {
            return allProjects;
        }
        
        // 否则返回该地址对应的项目列表
        return addressToProjects[addr];
    }
    
    /**
     * @dev 获取所有项目ID
     * @return projects 所有项目ID数组
     */
    function getAllProjects() external view override returns (bytes32[] memory projects) {
        return allProjects;
    }
}