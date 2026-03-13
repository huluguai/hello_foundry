// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MyToken} from "./my_token.sol";
import {ITokenRecipient} from "./ITokenRecipient.sol";

/**
 * @title MyTokenV2 - ERC20 Token with Hook Support
 * @dev Extends MyToken with transferWithCallback functionality
 */

contract MyTokenV2 is MyToken {
    
    
    // ==================== 事件定义 ====================
    
    /**
     * @notice 带回调的转账事件
     * @param from 转出地址（索引字段）
     * @param to 转入地址（索引字段）
     * @param value 转账金额（最小单位）
     * @param data 附加数据
     */
    event TransferWithCallback(address indexed from, address indexed to, uint256 value, bytes data);
    
    // ==================== 构造函数 ====================
    
    /**
     * @notice 构造函数
     * @param _initialSupply 初始供应量（以代币为单位）
     */
    constructor(uint256 _initialSupply) MyToken(_initialSupply) {}
    
    // ==================== 核心功能 ====================
    
    /**
     * @notice 向指定地址转账并在目标地址是合约时调用回调
     * @dev 如果目标地址是合约，会调用其 tokensReceived() 方法
     * @param to 接收方地址
     * @param value 转账金额（代币单位）
     * @param data 传递给回调函数的附加数据
     * @return 是否成功
     */
    function transferWithCallback(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool) {
        // 防止转账到零地址
        require(to != address(0), "Transfer to zero address");
        
        // 将代币单位转换为最小单位（带精度）
        uint256 valueInWei = value * (10 ** uint256(decimals));
        
        // 检查余额是否充足
        require(balanceOf[msg.sender] >= valueInWei, "Insufficient balance");
        
        // 更新双方余额
        unchecked {
            balanceOf[msg.sender] -= valueInWei;
            balanceOf[to] += valueInWei;
        }
        
        // 发出转账事件
        emit Transfer(msg.sender, to, valueInWei);
        emit TransferWithCallback(msg.sender, to, valueInWei, data);
        
        // 如果目标地址是合约，调用其 tokensReceived 方法
        if (isContract(to)) {
            bool success = ITokenRecipient(to).tokensReceived(
                msg.sender,
                to,
                valueInWei,
                data
            );
            require(success, "tokensReceived callback failed");
        }
        
        return true;
    }
    
    /**
     * @notice 判断一个地址是否为合约地址
     * @dev 通过 extcodesize 来判断
     * @param addr 要检查的地址
     * @return 如果是合约返回 true，否则返回 false
     */
    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}