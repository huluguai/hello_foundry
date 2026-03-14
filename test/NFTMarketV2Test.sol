// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {NFTMarket} from "../src/v2/mynft/NFTMarketV2.sol";
import {MyTokenV2} from "../src/v2/mytoken/my_token_v2.sol";
import {MyURINFT} from "../src/v2/mynft/MyBasicNFT.sol";

contract NFTMarketV2Test is Test {
    NFTMarket public market;
    MyTokenV2 public token;
    MyURINFT public nft;

    address public seller;
    address public buyer;

    uint256 public tokenId = 1;
    uint256 public price = 100; // 100 个 TOKEN（代币单位）

    function setUp() public {
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");

        // 部署 MyTokenV2（100万初始供应）
        token = new MyTokenV2(1_000_000);
        // 部署 MyURINFT
        nft = new MyURINFT();
        // 部署 NFTMarket
        market = new NFTMarket(address(token));

        // 给卖家铸造 NFT
        nft.mint(seller, "ipfs://test-uri-1");
        tokenId = nft.currentTokenId();

        // 给买家转 1000 个 TOKEN（代币单位）
        token.transfer(buyer, 1000);

        vm.label(seller, "seller");
        vm.label(buyer, "buyer");
        vm.label(address(market), "NFTMarket");
        vm.label(address(token), "MyTokenV2");
        vm.label(address(nft), "MyURINFT");
    }

    // ==================== 上架测试 ====================

    function test_List_Success() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);

        vm.expectEmit(true, true, true, true);
        emit NFTMarket.Listed(0, seller, address(nft), tokenId, price * 1e18);

        uint256 listingId = market.list(address(nft), tokenId, price);

        (
            address listedSeller,
            address listedNftContract,
            uint256 listedTokenId,
            uint256 listedPriceInWei,
            bool isActive
        ) = market.listings(listingId);

        assertEq(listedSeller, seller);
        assertEq(listedNftContract, address(nft));
        assertEq(listedTokenId, tokenId);
        assertEq(listedPriceInWei, price * 1e18);
        assertTrue(isActive);
        assertEq(listingId, 0);
        assertEq(market.nextListingId(), 1);
        assertEq(market.getPriceInTokenUnits(listingId), price);
        vm.stopPrank();
    }

    function test_List_RevertWhen_NotOwner() public {
        vm.prank(buyer);
        vm.expectRevert("Not owner nor approved");
        market.list(address(nft), tokenId, price);
    }

    function test_List_RevertWhen_ZeroNftContract() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        vm.expectRevert("Invalid NFT contract");
        market.list(address(0), tokenId, price);
        vm.stopPrank();
    }

    function test_List_RevertWhen_ZeroPrice() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        vm.expectRevert("Price must be > 0");
        market.list(address(nft), tokenId, 0);
        vm.stopPrank();
    }

    function test_List_RevertWhen_AlreadyListed() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, price);
        vm.expectRevert("Already listed");
        market.list(address(nft), tokenId, price + 1);
        vm.stopPrank();
    }

    function test_List_ByApprovedOperator() public {
        address operator = makeAddr("operator");
        vm.startPrank(seller);
        nft.setApprovalForAll(operator, true);
        vm.stopPrank();

        vm.prank(operator);
        uint256 listingId = market.list(address(nft), tokenId, price);

        (address listedSeller,,,,) = market.listings(listingId);
        assertEq(listedSeller, seller);
    }

    // ==================== 下架测试 ====================

    function test_Unlist_Success() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);

        vm.expectEmit(true, true, false, false);
        emit NFTMarket.Unlisted(listingId, seller);
        market.unlist(listingId);

        (,,,, bool isActive) = market.listings(listingId);
        assertFalse(isActive);
        vm.stopPrank();
    }

    function test_Unlist_RevertWhen_NotListed() public {
        vm.prank(seller);
        vm.expectRevert("Not listed");
        market.unlist(0);
    }

    function test_Unlist_RevertWhen_NotLister() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert("Not lister");
        market.unlist(listingId);
    }

    // ==================== buyNFT 购买测试 ====================

    function test_BuyNFT_Success() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), price);

        vm.expectEmit(true, true, true, true);
        emit NFTMarket.Sold(listingId, buyer, seller, address(nft), tokenId, price * 1e18);
        market.buyNFT(listingId, price);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(token.balanceOf(seller), price * 1e18);
        (,,,, bool isActive) = market.listings(listingId);
        assertFalse(isActive);
        vm.stopPrank();
    }

    function test_BuyNFT_RevertWhen_NotListed() public {
        vm.startPrank(buyer);
        token.approve(address(market), price);
        vm.expectRevert("Not listed");
        market.buyNFT(0, price);
        vm.stopPrank();
    }

    function test_BuyNFT_RevertWhen_InsufficientAmount() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), price - 1);
        vm.expectRevert("Insufficient amount");
        market.buyNFT(listingId, price - 1);
        vm.stopPrank();
    }

    function test_BuyNFT_RevertWhen_BoughtTwice() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), price);
        market.buyNFT(listingId, price);
        vm.expectRevert("Not listed");
        market.buyNFT(listingId, price);
        vm.stopPrank();
    }

    // ==================== transferWithCallback 购买测试 ====================

    function test_TransferWithCallback_BuySuccess() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        bytes memory data = abi.encode(listingId);

        vm.expectEmit(true, true, true, true);
        emit NFTMarket.Sold(listingId, buyer, seller, address(nft), tokenId, price * 1e18);
        token.transferWithCallback(address(market), price, data);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(token.balanceOf(seller), price * 1e18);
        (,,,, bool isActive) = market.listings(listingId);
        assertFalse(isActive);
        vm.stopPrank();
    }

    function test_TransferWithCallback_RefundExcess() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 overpay = price + 50;
        vm.startPrank(buyer);
        token.transfer(buyer, 50); // 确保有足够余额
        uint256 buyerBalanceBefore = token.balanceOf(buyer);

        token.transferWithCallback(address(market), overpay, abi.encode(listingId));

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(token.balanceOf(seller), price * 1e18);
        assertEq(token.balanceOf(buyer), buyerBalanceBefore - overpay * 1e18 + 50 * 1e18);
        vm.stopPrank();
    }

    function test_TransferWithCallback_RevertWhen_InvalidData() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert("Invalid data: need listingId");
        token.transferWithCallback(address(market), price, "");
        vm.stopPrank();
    }

    function test_TransferWithCallback_RevertWhen_InsufficientAmount() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert("Insufficient amount");
        token.transferWithCallback(address(market), price - 1, abi.encode(listingId));
        vm.stopPrank();
    }

    // ==================== 不变性测试 ====================

    function test_Invariant_MarketHoldsNoTokens() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), price);
        market.buyNFT(listingId, price);
        vm.stopPrank();

        assertEq(token.balanceOf(address(market)), 0, "Market should hold no tokens after buyNFT");

        // 再次上架并用 transferWithCallback 购买
        vm.startPrank(buyer);
        nft.approve(address(market), tokenId);
        listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        token.transfer(seller, 1000);
        vm.startPrank(seller);
        token.transferWithCallback(address(market), price, abi.encode(listingId));
        vm.stopPrank();

        assertEq(token.balanceOf(address(market)), 0, "Market should hold no tokens after transferWithCallback");
    }
}