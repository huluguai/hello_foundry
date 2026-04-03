// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MyURINFTUpgradeable} from "../src/v2/mynft/upgradeable/MyURINFTUpgradeable.sol";

contract MyURINFTUpgradeableTest is Test {
    MyURINFTUpgradeable internal impl;
    MyURINFTUpgradeable internal nft;

    address internal user = makeAddr("user");

    function setUp() public {
        impl = new MyURINFTUpgradeable();
        bytes memory init = abi.encodeCall(MyURINFTUpgradeable.initialize, ("MyURINFT", "MUN", address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);
        nft = MyURINFTUpgradeable(address(proxy));
    }

    function test_MintAndURI() public {
        nft.mint(user, "ipfs://a");
        assertEq(nft.ownerOf(1), user);
        assertEq(nft.tokenURI(1), "ipfs://a");
        assertEq(nft.currentTokenId(), 1);
    }

    function test_Mint_RevertWhen_NotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        nft.mint(user, "ipfs://x");
    }

    function test_Upgrade_OnlyOwner() public {
        MyURINFTUpgradeable v2 = new MyURINFTUpgradeable();
        vm.prank(user);
        vm.expectRevert();
        nft.upgradeToAndCall(address(v2), "");

        nft.upgradeToAndCall(address(v2), "");
    }
}
