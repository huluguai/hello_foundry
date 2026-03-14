// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {NFTMarket} from "../src/v2/mynft/NFTMarketV2.sol";

/**
 * @title DeployNFTMarketV2 - 部署 NFTMarket 到测试网
 * @notice 需要传入已部署的 MyTokenV2 地址
    NFTMarket deployed at: 0x4070357cde971f4531d7734ec9b1a717b79124ee
 */
contract DeployNFTMarketV2 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // 已部署的 MyTokenV2 地址
        address tokenV2Address = vm.envOr(
            "MYTOKENV2_ADDRESS",
            address(0x0b18F517d8e66b3bd6fB799d44A0ebee473Df20C)
        );

        vm.startBroadcast(deployerPrivateKey);

        NFTMarket market = new NFTMarket(tokenV2Address);

        vm.stopBroadcast();

        console.log("NFTMarket deployed at:", address(market));
        console.log("Token (MyTokenV2) address:", tokenV2Address);
    }
}
