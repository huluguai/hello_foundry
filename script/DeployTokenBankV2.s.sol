// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {XZXToken} from "../src/v2/mytoken/xzx_token.sol";
import {TokenBankV2} from "../src/v2/mytoken/token_bank_v2.sol";

/**
 * @title DeployTokenBankV2 - 部署 XZXToken（EIP-2612）与 TokenBankV2
 * @notice 先部署 XZXToken，再部署 TokenBankV2（传入代币地址）
 */
contract DeployTokenBankV2 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000));

        vm.startBroadcast(deployerPrivateKey);

        XZXToken xzx = new XZXToken(initialSupply);
        TokenBankV2 bankV2 = new TokenBankV2(address(xzx));

        vm.stopBroadcast();

        console.log("XZXToken deployed at:", address(xzx));
        console.log("TokenBankV2 deployed at:", address(bankV2));
        console.log("Initial supply (whole tokens):", initialSupply);
    }
}
