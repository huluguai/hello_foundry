// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {NFTMarketUpgradeableV1} from "../src/v2/mynft/upgradeable/NFTMarketUpgradeableV1.sol";
import {NFTMarketUpgradeableV2} from "../src/v2/mynft/upgradeable/NFTMarketUpgradeableV2.sol";

/**
 * @notice 将已部署的市场代理升级至 V2（`listWithSig`）
 * @dev 环境变量：PRIVATE_KEY（须为代理 owner）；NFT_MARKET_PROXY
 */
contract UpgradeNFTMarketToV2 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxy = vm.envAddress("NFT_MARKET_PROXY");

        vm.startBroadcast(deployerPrivateKey);

        NFTMarketUpgradeableV2 newImpl = new NFTMarketUpgradeableV2();
        NFTMarketUpgradeableV1(proxy).upgradeToAndCall(address(newImpl), "");

        vm.stopBroadcast();

        console.log("NFT_MARKET_PROXY:", proxy);
        console.log("NFTMarketUpgradeableV2 implementation:", address(newImpl));
    }
}
