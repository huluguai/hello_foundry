// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MyTokenV2} from "../src/v2/mytoken/my_token_v2.sol";
import {TokenBankV2} from "../src/v2/mytoken/token_bank_v2.sol";

/**
 * @title DeployTokenBankV2 - 部署 MyTokenV2 和 TokenBankV2 到测试网
 * @notice 部署顺序：先部署 MyTokenV2，再部署 TokenBankV2（依赖 MyTokenV2 地址）
    MyTokenV2 deployed at: 0x0b18F517d8e66b3bd6fB799d44A0ebee473Df20C
  TokenBankV2 deployed at: 0xBB5Dce153B4bF0b0106b47A93957f55e3fC28d41
 */
contract DeployTokenBankV2 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000));

        vm.startBroadcast(deployerPrivateKey);

        MyTokenV2 tokenV2 = new MyTokenV2(initialSupply);
        TokenBankV2 bankV2 = new TokenBankV2(address(tokenV2));

        vm.stopBroadcast();

        console.log("MyTokenV2 deployed at:", address(tokenV2));
        console.log("TokenBankV2 deployed at:", address(bankV2));
        console.log("Initial supply:", initialSupply);
    }
}