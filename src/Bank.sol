// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
contract Bank {
    address public immutable ADMIN; 
    mapping(address => uint) public deposits;
    
    // 存储存款金额前3名的地址
    address[3] public topDepositors;

    uint8 private constant TOP_COUNT = 3;
    
    constructor() {
        //构造函数执行的时候指定部署合约的人就是管理员
        ADMIN = msg.sender;
    }
    
    // 接收ETH并记录存款
    receive() external payable { 
        _handleDeposit();
    }
    
    // 存款函数，允许用户显式调用存款
    function deposit() external payable {
        _handleDeposit();
    }
    
    function _handleDeposit() internal {
        // 更新用户存款金额
        deposits[msg.sender] += msg.value;
        updateTopDepositors(msg.sender);
    }
    
    // 更新前3名存款人
    function updateTopDepositors(address depositor) internal {
        uint depositorBalance = deposits[depositor];
        
        // 如果存款人已经在前3名中，直接更新排序
        for (uint8 i = 0; i < TOP_COUNT; i++) {
            if (topDepositors[i] == depositor) {
                _updateRanking();
                return;
            }
        }
        
        // 检查是否应该加入前3名
        for (uint8 i = 0; i < TOP_COUNT; i++) {
            address currentAddr = topDepositors[i];
            // 如果位置为空或者新存款人的存款金额大于当前位置的存款金额
            if (currentAddr == address(0) || depositorBalance > deposits[currentAddr]) {
                // 将新存款人插入到当前位置，并将其他存款人向后移动
                for (uint8 j = 2; j > i; j--) {
                    topDepositors[j] = topDepositors[j-1];
                }
                topDepositors[i] = depositor;
                break;
            }
        }
    }
    
    function _updateRanking() internal {
        for (uint8 i = 1; i < TOP_COUNT; i++) {
            address key = topDepositors[i];
            if (key == address(0)) continue; // 跳过空地址
            
            uint keyDeposit = deposits[key];
            uint8 j = i;

            while (j > 0) {
                uint8 prev = j - 1;
                address prevAddr = topDepositors[prev];
                if (prevAddr == address(0) || deposits[prevAddr] < keyDeposit) {
                    topDepositors[j] = prevAddr;
                    j = prev;
                } else {
                    break;
                }
            }

            topDepositors[j] = key;
        }
    }
    
    // 获取前3名存款人及其存款金额
    function getTopDepositors() external view returns (address[3] memory, uint[3] memory) {
        uint[3] memory amounts;
        for (uint8 i = 0; i < TOP_COUNT; i++) {
            amounts[i] = deposits[topDepositors[i]];
        }
        return (topDepositors, amounts);
    }
    
    // 只有管理员可以提取所有ETH
    function withdraw() external {
        // 检查调用者是否为管理员
        require(msg.sender == ADMIN, "Only admin can withdraw");
        
        // 获取合约余额
        uint balance = address(this).balance;
        
        // 确保有余额可提取
        require(balance > 0, "No balance to withdraw");
        
        // 将所有ETH转给管理员
        (bool success, ) = ADMIN.call{value: balance}("");
        require(success, "Withdrawal failed");
    }
}