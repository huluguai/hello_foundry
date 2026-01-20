// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {BaseERC20} from "../src/BaseERC20.sol";
import {TokenBank} from "../src/TokenBank.sol";

contract TokenBankScript is Script {
    TokenBank public tokenBank;
    BaseERC20 public baseERC20;
    
    function run() public {
        // 从环境变量获取私钥（如果设置了）
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        baseERC20 = new BaseERC20();
        tokenBank = new TokenBank(address(baseERC20));
        
        vm.stopBroadcast();
        
        // 输出部署信息
        console.log("BaseERC20 deployed at:", address(baseERC20));
        console.log("TokenBank deployed at:", address(tokenBank));
    }
}