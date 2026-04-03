// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {NFTMarket} from "../src/v2/mynft/NFTMarketV2.sol";

/**
 * @title DeployNFTMarketV2 - 部署 NFTMarket（EIP-712 白名单购买）
 * @notice 环境变量：
    NFTMarket	0x84D6B75ddE24F0398aD2033f610bAAd483f52Cb1
    支付代币 (PAYMENT_TOKEN_ADDRESS)	0xbc03cE92d313a0380d84A619aB8f79915ad66C09
    白名单签名地址 (WHITELIST_SIGNER)	0xfd8890Be36244f4270602B1F46717882c5ffDf47（与未设置 WHITELIST_SIGNER 时的部署者一致）
 *   - PAYMENT_TOKEN_ADDRESS：支付用 ERC20（需实现 decimals()，如 XZXToken）
 *   - WHITELIST_SIGNER（可选）：签发 PermitBuy 的地址；默认与部署者地址相同
 */
contract DeployNFTMarketV2 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address paymentToken = vm.envOr(
            "PAYMENT_TOKEN_ADDRESS",
            address(0xbc03cE92d313a0380d84A619aB8f79915ad66C09)
        );
        address whitelistSigner = vm.envOr("WHITELIST_SIGNER", deployer);

        vm.startBroadcast(deployerPrivateKey);

        NFTMarket market = new NFTMarket(paymentToken, whitelistSigner);

        vm.stopBroadcast();

        console.log("NFTMarket deployed at:", address(market));
        console.log("Payment token:", paymentToken);
        console.log("Whitelist signer:", whitelistSigner);
    }
}
