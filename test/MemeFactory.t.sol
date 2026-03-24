// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeFactory} from "../src/v2/meme/MemeFactory.sol";
import {MemeToken} from "../src/v2/meme/MemeToken.sol";

contract MemeFactoryTest is Test {
    MemeFactory internal factory;
    address internal project;
    address internal issuer;
    address internal buyer;

    function setUp() public {
        project = makeAddr("project");
        issuer = makeAddr("issuer");
        buyer = makeAddr("buyer");
        factory = new MemeFactory(project);
    }

    function test_FeeSplit_1ether() public {
        vm.prank(issuer);
        address token = factory.deployMeme("DOGE", 1_000 ether, 100 ether, 0.01 ether);
        uint256 pay = (MemeToken(token).perMint() * MemeToken(token).price()) / 10 ** MemeToken(token).decimals();
        assertEq(pay, 1 ether);

        uint256 platformBefore = project.balance;
        uint256 issuerBefore = issuer.balance;

        vm.deal(buyer, pay);
        vm.prank(buyer);
        factory.mintMeme{value: pay}(token);

        uint256 platformFee = pay / 100;
        uint256 creatorShare = pay - platformFee;
        assertEq(project.balance - platformBefore, platformFee);
        assertEq(issuer.balance - issuerBefore, creatorShare);
        assertEq(MemeToken(token).balanceOf(buyer), MemeToken(token).perMint());
    }

    function test_FeeSplit_smallAmount() public {
        vm.prank(issuer);
        address token = factory.deployMeme("SMOL", 100 ether, 10 ether, 3); // (10e18 * 3) / 1e18 = 30 wei
        uint256 pay = (10 ether * 3) / 10 ** MemeToken(token).decimals();

        vm.deal(buyer, pay);
        vm.prank(buyer);
        factory.mintMeme{value: pay}(token);

        assertEq(project.balance, pay / 100); // 0
        assertEq(issuer.balance, pay); // all to creator when platform rounds down
    }

    function test_MintCount_respectsMaxSupply() public {
        uint256 maxSupply = 250 ether;
        uint256 perMint = 100 ether;
        vm.prank(issuer);
        address token = factory.deployMeme("CAP", maxSupply, perMint, 1);

        uint256 cost = (perMint * 1) / 10 ** MemeToken(token).decimals();
        vm.deal(buyer, cost * 10);

        vm.startPrank(buyer);
        factory.mintMeme{value: cost}(token);
        assertEq(MemeToken(token).totalSupply(), perMint);

        factory.mintMeme{value: cost}(token);
        assertEq(MemeToken(token).totalSupply(), 200 ether);
        vm.expectRevert(bytes("MemeToken: cap exceeded"));
        factory.mintMeme{value: cost}(token);
        vm.stopPrank();

        assertEq(MemeToken(token).totalSupply(), 200 ether);
    }

    function test_Revert_unknownToken() public {
        MemeToken rogue = new MemeToken(address(factory));
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(bytes("MemeFactory: unknown meme"));
        factory.mintMeme{value: 1 ether}(address(rogue));
    }

    function test_Revert_wrongPayment() public {
        vm.prank(issuer);
        address token = factory.deployMeme("X", 1000 ether, 10 ether, 2 wei);
        uint256 expected = (10 ether * 2) / 10 ** MemeToken(token).decimals();
        vm.deal(buyer, expected + 100);
        vm.prank(buyer);
        vm.expectRevert(bytes("MemeFactory: wrong payment"));
        factory.mintMeme{value: expected - 1}(token);
    }
}
