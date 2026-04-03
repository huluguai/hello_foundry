// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {AirdopMerkleNFTMarket} from "../src/v2/mynft/AirdopMerkleNFTMarket.sol";

/**
 * @title DeployAirdopMerkleNFTMarket
 * @notice 环境变量：
 *   - PAYMENT_TOKEN_ADDRESS：支付用 ERC20（须支持 EIP-2612 Permit + decimals()，如 XZXToken）
 *   - MERKLE_ROOT（可选）：bytes32，十六进制；未设置则为 0x00..00（部署后请 owner 调用 setMerkleRoot）
 */
contract DeployAirdopMerkleNFTMarket is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address paymentToken = vm.envAddress("PAYMENT_TOKEN_ADDRESS");
        bytes32 merkleRoot = vm.envOr("MERKLE_ROOT", bytes32(0));

        vm.startBroadcast(deployerPrivateKey);

        AirdopMerkleNFTMarket market = new AirdopMerkleNFTMarket(paymentToken, merkleRoot);

        vm.stopBroadcast();

        console.log("AirdopMerkleNFTMarket deployed at:", address(market));
        console.log("Payment token:", paymentToken);
        console.logBytes32(merkleRoot);
        console.log("Deployer (owner):", deployer);
    }
}
