// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

 import {MyToken} from "./my_token.sol";

/**
 * @title TokenBank - 代币存储合约
 * @dev 允许用户存入和取出 MyToken，并记录每个用户的存款余额
 */
contract TokenBank {
    // ==================== 状态变量 ====================
    
    /// @notice MyToken 代币合约实例
    MyToken public token;
    
    /// @notice 记录每个用户的存款余额（最小单位）
    mapping(address => uint256) public deposits;
    
    /// @notice 记录所有存款用户的地址列表
    address[] public depositors;
    
    /// @notice 检查某个地址是否已经存过款
    mapping(address => bool) public hasDeposited;
    
    // ==================== 事件定义 ====================
    
    /**
     * @notice 存款事件
     * @param user 存款用户地址
     * @param amount 存款金额（最小单位）
     * @param timestamp 存款时间戳
     */
    event Deposit(address indexed user, uint256 amount, uint256 timestamp);
    
    /**
     * @notice 取款事件
     * @param user 取款用户地址
     * @param amount 取款金额（最小单位）
     * @param timestamp 取款时间戳
     */
    event Withdraw(address indexed user, uint256 amount, uint256 timestamp);
    
    // ==================== 构造函数 ====================
    
    /**
     * @notice 合约部署时初始化
     * @dev 设置 MyToken 代币合约地址
     * @param _tokenAddress MyToken 合约地址
     */
    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Invalid token address");
        token = MyToken(_tokenAddress);
    }
    
    // ==================== 核心功能 ====================
    
    /**
     * @notice 存入代币到 Bank
     * @dev 用户需要先授权 TokenBank 使用其代币，然后调用此方法
     * @param amount 存入的代币数量（代币单位）
     * @return 是否成功
     */
    function deposit(uint256 amount) external virtual returns (bool) {
        // 检查存入数量必须大于 0
        require(amount > 0, "Deposit amount must be greater than 0");
        
        // 检查用户余额是否足够
        require(token.balanceOf(msg.sender) >= amount * (10 ** uint256(token.decimals())), "Insufficient token balance");
        
        // 从用户转账到 TokenBank 合约（传入代币单位，my_token 内部会转换）
        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");
        
        // 更新用户存款余额（存储最小单位）
        deposits[msg.sender] += amount * (10 ** uint256(token.decimals()));
        
        // 如果是首次存款，添加到存款人列表
        if (!hasDeposited[msg.sender]) {
            hasDeposited[msg.sender] = true;
            depositors.push(msg.sender);
        }
        
        // 发出存款事件
        emit Deposit(msg.sender, amount * (10 ** uint256(token.decimals())), block.timestamp);
        
        return true;
    }
    
    /**
     * @notice 从 Bank 提取代币
     * @dev 用户只能提取自己的存款
     * @param amount 提取的代币数量（代币单位）
     * @return 是否成功
     */
    function withdraw(uint256 amount) external returns (bool) {
        // 检查提取数量必须大于 0
        require(amount > 0, "Withdraw amount must be greater than 0");
        
        // 将代币单位转换为最小单位
        uint256 amountInWei = amount * (10 ** uint256(token.decimals()));
        
        // 检查用户存款余额是否足够
        require(deposits[msg.sender] >= amountInWei, "Insufficient deposit balance");
        
        // 更新用户存款余额
        unchecked {
            deposits[msg.sender] -= amountInWei;
        }
        
        // 从 TokenBank 合约转账给用户（传入代币单位，my_token 内部会转换）
        bool success = token.transfer(msg.sender, amount);
        require(success, "Transfer failed");
        
        // 如果存款已取完，可以从存款人列表中移除（可选优化）
        if (deposits[msg.sender] == 0) {
            hasDeposited[msg.sender] = false;
        }
        
        // 发出取款事件
        emit Withdraw(msg.sender, amountInWei, block.timestamp);
        
        return true;
    }
    
    // ==================== 查询功能 ====================
    
    /**
     * @notice 获取用户的存款余额（代币单位）
     * @dev 方便前端查询显示
     * @param user 用户地址
     * @return 存款余额（代币单位）
     */
    function getDepositBalance(address user) external view returns (uint256) {
        return deposits[user] / (10 ** uint256(token.decimals()));
    }
    
    /**
     * @notice 获取所有存款人的地址列表
     * @dev 用于查询所有参与存款的用户
     * @return 存款人地址数组
     */
    function getAllDepositors() external view returns (address[] memory) {
        return depositors;
    }
    
    /**
     * @notice 获取存款人总数
     * @dev 统计有多少个不同的存款用户
     * @return 存款人数量
     */
    function getDepositorsCount() external view returns (uint256) {
        return depositors.length;
    }
    
    /**
     * @notice 获取合约中存储的代币总余额
     * @dev 查看 TokenBank 中还有多少代币
     * @return 合约代币余额（代币单位）
     */
    function getTotalBalance() external view returns (uint256) {
        return token.balanceOf(address(this)) / (10 ** uint256(token.decimals()));
    }
}