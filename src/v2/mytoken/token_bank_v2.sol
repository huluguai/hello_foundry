// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TokenBank} from "./token_bank.sol";
import {MyTokenV2} from "./my_token_v2.sol";

/**
 * @title TokenBankV2 - Enhanced TokenBank with Hook Support
 * @dev Supports direct deposits via transferWithCallback from MyTokenV2
 */
contract TokenBankV2 is TokenBank {
    
    // ==================== 状态变量 ====================
    
    /// @notice MyTokenV2 代币合约实例
    MyTokenV2 public tokenV2;
    
    // ==================== 事件定义 ====================
    
    /**
     * @notice 通过 Hook 存款事件
     * @param user 存款用户地址
     * @param amount 存款金额（最小单位）
     * @param timestamp 存款时间戳
     * @param data 附加数据
     */
    event DepositViaHook(address indexed user, uint256 amount, uint256 timestamp, bytes data);
    
    // ==================== 构造函数 ====================
    
    /**
     * @notice 合约部署时初始化
     * @dev 设置 MyTokenV2 代币合约地址
     * @param _tokenAddress MyTokenV2 合约地址
     */
    constructor(address _tokenAddress) TokenBank(_tokenAddress) {
        require(_tokenAddress != address(0), "Invalid token address");
        tokenV2 = MyTokenV2(_tokenAddress);
    }
    
    // ==================== Hook 回调函数 ====================
    
    /**
     * @notice 接收代币时的回调函数
     * @dev 当用户通过 transferWithCallback 直接转账到 TokenBankV2 时触发
     * @param from 发送者地址
     * @param to 接收者地址（本合约地址）
     * @param amount 接收的金额（最小单位）
     * @param data 附加数据
     * @return 是否成功
     */
    function tokensReceived(
        address from,
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        // 确保只有来自指定的 TokenV2 合约的转账才被接受
        require(msg.sender == address(tokenV2), "Only accepts tokens from specified token contract");
        
        // 确保是转账到这个合约
        require(to == address(this), "Tokens not sent to this contract");
        
        // 更新用户存款余额
        deposits[from] += amount;
        
        // 如果是首次存款，添加到存款人列表
        if (!hasDeposited[from]) {
            hasDeposited[from] = true;
            depositors.push(from);
        }
        
        // 发出存款事件（包含附加数据）
        emit Deposit(from, amount, block.timestamp);
        emit DepositViaHook(from, amount, block.timestamp, data);
        
        return true;
    }
    
    // ==================== 覆盖父合约的 deposit 函数 ====================
    
    /**
     * @notice 存入代币到 Bank（支持 MyToken 和 MyTokenV2）
     * @dev 用户需要先授权 TokenBankV2 使用其代币，然后调用此方法
     * @param amount 存入的代币数量（代币单位）
     * @return 是否成功
     */
    function deposit(uint256 amount) external override returns (bool) {
        // 检查存入数量必须大于 0
        require(amount > 0, "Deposit amount must be greater than 0");
        
        // 检查用户余额是否足够
        require(token.balanceOf(msg.sender) >= amount * (10 ** uint256(token.decimals())), "Insufficient token balance");
        
        // 从用户转账到 TokenBankV2 合约
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
}