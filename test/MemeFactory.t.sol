// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "../lib/forge-std/src/Test.sol";
import {MemeFactory} from "../src/v2/meme/MemeFactory.sol";
import {MemeToken} from "../src/v2/meme/MemeToken.sol";
import {MockUniswapFactory, MockUniswapV2Router, MockPair} from "./mocks/MockUniswap.sol";

contract MemeFactoryTest is Test {
    MemeFactory internal factory;
    MockUniswapFactory internal uniFactory;
    MockUniswapV2Router internal router;
    address internal weth;
    address internal project;
    address internal issuer;
    address internal buyer;

    function setUp() public {
        project = makeAddr("project");
        issuer = makeAddr("issuer");
        buyer = makeAddr("buyer");
        weth = makeAddr("WETH");
        uniFactory = new MockUniswapFactory();
        router = new MockUniswapV2Router(weth, uniFactory);
        factory = new MemeFactory(project, address(router));
    }

    function _registerPair(address token) internal {
        MockPair pair = new MockPair(token, weth);
        uniFactory.setPair(address(pair));
    }

    function test_FeeSplit_1ether() public {
        vm.prank(issuer);
        address token = factory.deployMeme("DOGE", 1_000 ether, 100 ether, 0.01 ether);
        _registerPair(token);

        uint256 pay = (MemeToken(token).perMint() * MemeToken(token).price()) / 10 ** MemeToken(token).decimals();
        assertEq(pay, 1 ether);

        uint256 liquidityEth = (pay * 5) / 100;
        uint256 creatorShare = pay - liquidityEth;
        uint256 issuerBefore = issuer.balance;

        vm.deal(buyer, pay);
        vm.prank(buyer);
        factory.mintMeme{value: pay}(token);

        assertEq(issuer.balance - issuerBefore, creatorShare);
        assertEq(MemeToken(token).balanceOf(buyer), MemeToken(token).perMint());
        assertEq(router.lastAddLiquidityEth(), liquidityEth);
        assertEq(router.lastAddLiquidityTo(), project);
        assertGt(router.lpToken().balanceOf(project), 0);
    }

    function test_FeeSplit_smallAmount_ZeroLiquidityEth() public {
        // cost = 19 wei => floor(19 * 5 / 100) = 0，不加池，creator 收到全部 ETH
        vm.prank(issuer);
        address token = factory.deployMeme("SMOL", 100 ether, 19 ether, 1);
        _registerPair(token);
        uint256 pay = (19 ether * 1) / 10 ** MemeToken(token).decimals();
        assertEq(pay, 19);

        vm.deal(buyer, pay);
        vm.prank(buyer);
        factory.mintMeme{value: pay}(token);

        assertEq((pay * 5) / 100, 0);
        assertEq(router.lastAddLiquidityEth(), 0);
        assertEq(issuer.balance, pay);
    }

    function test_MintCount_respectsMaxSupply() public {
        uint256 maxSupply = 250 ether;
        uint256 perMint = 100 ether;
        vm.prank(issuer);
        address token = factory.deployMeme("CAP", maxSupply, perMint, 1);
        _registerPair(token);

        uint256 cost = (perMint * 1) / 10 ** MemeToken(token).decimals();
        uint256 liqEth = (cost * 5) / 100;
        uint256 tokenForLp = (liqEth * 10 ** MemeToken(token).decimals()) / MemeToken(token).price();
        uint256 perTx = perMint + tokenForLp;

        vm.deal(buyer, cost * 10);

        vm.startPrank(buyer);
        factory.mintMeme{value: cost}(token);
        assertEq(MemeToken(token).totalSupply(), perTx);

        factory.mintMeme{value: cost}(token);
        assertEq(MemeToken(token).totalSupply(), 2 * perTx);

        vm.expectRevert(bytes("MemeToken: cap exceeded"));
        factory.mintMeme{value: cost}(token);
        vm.stopPrank();

        assertEq(MemeToken(token).totalSupply(), 2 * perTx);
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
        _registerPair(token);
        uint256 expected = (10 ether * 2) / 10 ** MemeToken(token).decimals();
        vm.deal(buyer, expected + 100);
        vm.prank(buyer);
        vm.expectRevert(bytes("MemeFactory: wrong payment"));
        factory.mintMeme{value: expected - 1}(token);
    }

    function test_buyMeme_swapsWhenBetterThanMint() public {
        vm.prank(issuer);
        address token = factory.deployMeme("SWAP", 10_000 ether, 1 ether, 1 ether);
        _registerPair(token);

        uint256 ethIn = 1 ether;
        uint256 mintBaseline = (ethIn * 10 ** MemeToken(token).decimals()) / MemeToken(token).price();
        router.setMockAmountOut(mintBaseline + 1);

        deal(address(token), address(router), 1000 ether);
        vm.deal(buyer, ethIn);
        uint256 beforeBal = MemeToken(token).balanceOf(buyer);

        vm.prank(buyer);
        factory.buyMeme{value: ethIn}(token, mintBaseline + 1, block.timestamp + 300);

        assertEq(MemeToken(token).balanceOf(buyer) - beforeBal, mintBaseline + 1);
    }

    function test_buyMeme_revert_whenMintPriceBetterOrEqual() public {
        vm.prank(issuer);
        address token = factory.deployMeme("BAD", 10_000 ether, 1 ether, 1 ether);
        _registerPair(token);

        uint256 ethIn = 1 ether;
        uint256 mintBaseline = (ethIn * 10 ** MemeToken(token).decimals()) / MemeToken(token).price();
        router.setMockAmountOut(mintBaseline);

        deal(address(token), address(router), 1000 ether);
        vm.deal(buyer, ethIn);

        vm.prank(buyer);
        vm.expectRevert(bytes("MemeFactory: mint price better or equal"));
        factory.buyMeme{value: ethIn}(token, mintBaseline, block.timestamp + 300);
    }

    function test_buyMeme_revert_noPair() public {
        vm.prank(issuer);
        address token = factory.deployMeme("NOPAIR", 10_000 ether, 1 ether, 1 ether);
        uniFactory.setPair(address(0));

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(bytes("MemeFactory: no pair"));
        factory.buyMeme{value: 1 ether}(token, 1, block.timestamp + 300);
    }
}
