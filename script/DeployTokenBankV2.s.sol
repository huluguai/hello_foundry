// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {XZXToken} from "../src/v2/mytoken/xzx_token.sol";
import {TokenBankV2} from "../src/v2/mytoken/token_bank_v2.sol";

/// @dev Uniswap Permit2（Ethereum / Sepolia 等常见链同址）
address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

/**
 * @title DeployTokenBankV2 - 部署 XZXToken（EIP-2612）与 TokenBankV2
 * @notice 先部署 XZXToken，再部署 TokenBankV2（代币地址 + Permit2 地址）
 * xzx_token： 0x5256Db529A2AD34077bFC0F8b0c288df58AeB654.
 * token_bank_v2： 0xB156FAA36F54cbf177114d78A23EC26D2FFFE48F.
 * 环境变量（.env）：PRIVATE_KEY、INITIAL_SUPPLY、RPC_URL、ETHERSCAN_API_KEY
 *
 * 部署并开源（验证）Sepolia：
 *   source .env && forge script script/DeployTokenBankV2.s.sol:DeployTokenBankV2 --rpc-url sepolia --broadcast --verify -vvvv
 *
 * 或显式使用 .env 中的 RPC：
 *   source .env && forge script script/DeployTokenBankV2.s.sol:DeployTokenBankV2 --rpc-url "$RPC_URL" --broadcast --verify -vvvv
 */
contract DeployTokenBankV2 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000));

        vm.startBroadcast(deployerPrivateKey);

        XZXToken xzx = new XZXToken(initialSupply);
        TokenBankV2 bankV2 = new TokenBankV2(address(xzx), PERMIT2);

        vm.stopBroadcast();

        console.log("XZXToken deployed at:", address(xzx));
        console.log("TokenBankV2 deployed at:", address(bankV2));
        console.log("Initial supply (whole tokens):", initialSupply);
    }
}
