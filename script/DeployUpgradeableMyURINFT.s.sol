// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MyURINFTUpgradeable} from "../src/v2/mynft/upgradeable/MyURINFTUpgradeable.sol";

/**
 * @notice 部署可升级 ERC721（MyURINFTUpgradeable）实现 + 代理
 * @dev 环境变量：PRIVATE_KEY；NFT_NAME（可选，默认 MyURINFT）；NFT_SYMBOL（可选，默认 MUN）
 */
contract DeployUpgradeableMyURINFT is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        string memory name_ = vm.envOr("NFT_NAME", string("MyURINFT"));
        string memory symbol_ = vm.envOr("NFT_SYMBOL", string("MUN"));

        vm.startBroadcast(deployerPrivateKey);

        MyURINFTUpgradeable impl = new MyURINFTUpgradeable();
        bytes memory init = abi.encodeCall(MyURINFTUpgradeable.initialize, (name_, symbol_, deployer));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);

        vm.stopBroadcast();

        console.log("MyURINFTProxy (use this address):", address(proxy));
        console.log("MyURINFTUpgradeable implementation:", address(impl));
        console.log("Owner:", deployer);
    }
}
