// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title 预言机数据接口
 * @notice 接收链下数据上链，供业务合约读取数据
 */
interface IOracle {
    
    // ============ 事件 ============
    
    /**
     * @dev 数据提交事件
     * @param pid 项目ID
     * @param did 数据ID（格式：年月日，如"20231001"表示2023年10月1日）
     * @param submitter 提交者地址
     * @param timestamp 提交时间戳
     */
    event DataSubmitted(
        bytes32 indexed pid,
        bytes32 indexed did,
        address indexed submitter,
        uint256 timestamp
    );
    
    /**
     * @dev 项目注册事件
     * @param pid 项目ID
     * @param submitter 提交者地址
     * @param description 项目描述
     */
    event ProjectRegistered(
        bytes32 indexed pid,
        address indexed submitter,
        string description
    );
    
    // ============ 数据结构 ============
    
    /**
     * @dev 数据存储结构
     */
    struct OracleData {
        bytes32 pid;            // 项目ID
        bytes32 did;            // 数据ID（格式：年月日，如"20231001"表示2023年10月1日）
        bytes coreData;         // 核心数据（bytes类型）
        bytes32 dataHash;       // 总数据哈希
        address submitter;      // 提交者地址
        uint256 submitTime;     // 提交时间
    }
    
    /**
     * @dev 项目配置结构
     */
    struct ProjectConfig {
        bool isActive;          // 项目是否激活
        bytes description;      // 项目描述（bytes类型）
        address[] authorizedSubmitters; // 授权提交者列表
        uint256 dataTTL;        // 数据有效期（秒）
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
    ) external;
    
    /**
     * @dev 更新项目配置
     * @param pid 项目ID
     * @param dataTTL 数据有效期
     */
    function updateProjectConfig(
        bytes32 pid,
        uint256 dataTTL
    ) external;
    
    /**
     * @dev 添加授权提交者
     * @param pid 项目ID
     * @param submitter 提交者地址
     */
    function addAuthorizedSubmitter(
        bytes32 pid,
        address submitter
    ) external;
    
    // ============ 数据提交函数 ============
    
    /**
     * @dev 提交数据（限管理员、数据上传者或授权提交者）
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
    ) external;
    
    /**
     * @dev 批量提交数据（限管理员、数据上传者或授权提交者）
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
    ) external;
    
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
    ) external view returns (OracleData memory data);
    
    /**
     * @dev 获取项目配置
     * @param pid 项目ID
     * @return config 项目配置
     */
    function getProjectConfig(
        bytes32 pid
    ) external view returns (ProjectConfig memory config);
    
    /**
     * @dev 获取数据哈希
     * @param pid 项目ID
     * @param did 数据ID（格式：年月日，如"20231001"表示2023年10月1日）
     * @return dataHash 数据哈希
     */
    function getDataHash(
        bytes32 pid,
        bytes32 did
    ) external view returns (bytes32 dataHash);
    
    /**
     * @dev 获取核心数据
     * @param pid 项目ID
     * @param did 数据ID（格式：年月日，如"20231001"表示2023年10月1日）
     * @return coreData 核心数据
     */
    function getCoreData(
        bytes32 pid,
        bytes32 did
    ) external view returns (bytes memory coreData);
    
    /**
     * @dev 检查地址是否为授权提交者
     * @param pid 项目ID
     * @param submitter 提交者地址
     * @return 是否为授权提交者
     */
    function isAuthorizedSubmitter(
        bytes32 pid,
        address submitter
    ) external view returns (bool);
    
    /**
     * @dev 通过地址查询对应项目
     * @param addr 查询地址
     * @return projects 该地址作为授权提交者的所有项目ID
     */
    function getProjectsByAddress(
        address addr
    ) external view returns (bytes32[] memory projects);
    
    /**
     * @dev 获取所有项目ID
     * @return projects 所有项目ID数组
     */
    function getAllProjects() external view returns (bytes32[] memory projects);
    
    /**
     * @dev 获取项目的最新数据
     * @param pid 项目ID
     * @return data 最新数据详情
     */
    function getLatestData(bytes32 pid) external view returns (OracleData memory data);
    
    /**
     * @dev 获取项目的最新数据ID
     * @param pid 项目ID
     * @return did 最新数据ID
     */
    function getLatestDataId(bytes32 pid) external view returns (bytes32 did);
    
    /**
     * @dev 获取项目的所有数据ID
     * @param pid 项目ID
     * @return dids 所有数据ID数组
     */
    function getDataIds(bytes32 pid) external view returns (bytes32[] memory dids);
    
    /**
     * @dev 按前缀模糊查询数据ID
     * @param pid 项目ID
     * @param prefix 前缀（如0x323031330000...表示"2023"开头的日期）
     * @return matchingIds 匹配的数据ID数组
     */
    function getDataIdsByPrefix(bytes32 pid, bytes32 prefix) external view returns (bytes32[] memory matchingIds);
    
    /**
     * @dev 按年月查询数据ID
     * @param pid 项目ID
     * @param year 年份（如2023）
     * @param month 月份（1-12）
     * @return matchingIds 匹配的数据ID数组
     */
    function getDataIdsByYearMonth(bytes32 pid, uint16 year, uint8 month) external view returns (bytes32[] memory matchingIds);
    
    /**
     * @dev 查询指定年月的数据最新一条
     * @param pid 项目ID
     * @param year 年份（如2023）
     * @param month 月份（1-12）
     * @return data 最新数据详情
     */
    function getLatestDataByYearMonth(bytes32 pid, uint16 year, uint8 month) external view returns (OracleData memory data);
    
    /**
     * @dev 将年月日转换为标准的did格式
     * @param year 年份（如2023）
     * @param month 月份（1-12）
     * @param day 日期（1-31）
     * @return did 转换后的did（格式：年月日，如"20231001"表示2023年10月1日）
     */
    function encodeYearMonthDayToDid(uint16 year, uint8 month, uint8 day) external pure returns (bytes32 did);
    
    /**
     * @dev 从did中解析出年月日
     * @param did 数据ID（格式：年月日，如"20231001"表示2023年10月1日）
     * @return year 年份
     * @return month 月份
     * @return day 日期
     */
    function decodeDidToYearMonthDay(bytes32 did) external pure returns (uint16 year, uint8 month, uint8 day);
    
    /**
     * @dev 验证did是否为有效的年月日格式
     * @param did 数据ID
     * @return isValid 是否为有效的年月日格式
     */
    function isValidYearMonthDayDid(bytes32 did) external pure returns (bool isValid);
}