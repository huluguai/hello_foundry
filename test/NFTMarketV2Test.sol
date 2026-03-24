// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NFTMarket} from "../src/v2/mynft/NFTMarketV2.sol";
import {XZXToken} from "../src/v2/mytoken/xzx_token.sol";
import {MyTokenV2} from "../src/v2/mytoken/my_token_v2.sol";
import {MyURINFT} from "../src/v2/mynft/MyBasicNFT.sol";

contract NFTMarketV2Test is Test {
    NFTMarket public market;
    XZXToken public token;
    MyURINFT public nft;

    address public seller;
    address public buyer;

    uint256 internal constant SIGNER_PK = 0xA11CE;
    address public signer;

    uint256 public tokenId = 1;
    uint256 public price = 100;

    bytes32 internal constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant _PERMIT_BUY_TYPEHASH =
        keccak256("PermitBuy(address buyer,uint256 listingId,uint256 deadline)");

    function setUp() public {
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        signer = vm.addr(SIGNER_PK);

        token = new XZXToken(1_000_000);
        nft = new MyURINFT();
        market = new NFTMarket(address(token), signer);

        nft.mint(seller, "ipfs://test-uri-1");
        tokenId = nft.currentTokenId();

        token.transfer(buyer, 1000 * 1e18);

        vm.label(seller, "seller");
        vm.label(buyer, "buyer");
        vm.label(address(market), "NFTMarket");
        vm.label(address(token), "XZXToken");
        vm.label(address(nft), "MyURINFT");
        vm.label(signer, "whitelistSigner");
    }

    function _domainSeparator(NFTMarket m) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("1")),
                block.chainid,
                address(m)
            )
        );
    }

    function _permitDigest(address buyer_, uint256 listingId, uint256 deadline) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(_PERMIT_BUY_TYPEHASH, buyer_, listingId, deadline));
        return keccak256(abi.encodePacked(hex"1901", _domainSeparator(market), structHash));
    }

    function _signPermit(address buyer_, uint256 listingId, uint256 deadline) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 digest = _permitDigest(buyer_, listingId, deadline);
        return vm.sign(SIGNER_PK, digest);
    }

    // ==================== 上架测试 ====================

    function test_List_Success() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);

        vm.expectEmit(true, true, true, true);
        emit NFTMarket.Listed(0, seller, address(nft), tokenId, price * 1e18);

        uint256 listingId = market.list(address(nft), tokenId, price);

        (address listedSeller, address listedNftContract, uint256 listedTokenId, uint256 listedPriceInWei, bool isActive) =
            market.listings(listingId);

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

    // ==================== buyNFT 已禁用 ====================

    function test_BuyNFT_Reverts() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), price * 1e18);
        vm.expectRevert(NFTMarket.BuyNFTDisabled.selector);
        market.buyNFT(listingId, price);
        vm.stopPrank();
    }

    // ==================== permitBuy ====================

    function test_PermitBuy_Success() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(buyer, listingId, deadline);

        vm.startPrank(buyer);
        token.approve(address(market), price * 1e18);
        market.permitBuy(listingId, price, deadline, v, r, s);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(token.balanceOf(seller), price * 1e18);
        (,,,, bool isActive) = market.listings(listingId);
        assertFalse(isActive);
        vm.stopPrank();
    }

    function test_PermitBuy_RevertWhen_NotListed() public {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(buyer, 0, deadline);

        vm.startPrank(buyer);
        token.approve(address(market), price * 1e18);
        vm.expectRevert("Not listed");
        market.permitBuy(0, price, deadline, v, r, s);
        vm.stopPrank();
    }

    function test_PermitBuy_RevertWhen_InsufficientAmount() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(buyer, listingId, deadline);

        vm.startPrank(buyer);
        token.approve(address(market), price * 1e18);
        vm.expectRevert("Insufficient amount");
        market.permitBuy(listingId, price - 1, deadline, v, r, s);
        vm.stopPrank();
    }

    function test_PermitBuy_RevertWhen_ExpiredDeadline() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(buyer, listingId, deadline);

        vm.warp(block.timestamp + 101);

        vm.startPrank(buyer);
        token.approve(address(market), price * 1e18);
        vm.expectRevert("Permit expired");
        market.permitBuy(listingId, price, deadline, v, r, s);
        vm.stopPrank();
    }

    function test_PermitBuy_RevertWhen_WrongSigner() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 days;
        uint256 wrongPk = 0xB0B;
        bytes32 digest = _permitDigest(buyer, listingId, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);

        vm.startPrank(buyer);
        token.approve(address(market), price * 1e18);
        vm.expectRevert("Invalid permit signature");
        market.permitBuy(listingId, price, deadline, v, r, s);
        vm.stopPrank();
    }

    function test_PermitBuy_RevertWhen_BuyerMismatchInSignature() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        address other = makeAddr("other");
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(other, listingId, deadline);

        vm.startPrank(buyer);
        token.approve(address(market), price * 1e18);
        vm.expectRevert("Invalid permit signature");
        market.permitBuy(listingId, price, deadline, v, r, s);
        vm.stopPrank();
    }

    function test_PermitBuy_RevertWhen_SignerZero() public {
        NFTMarket m = new NFTMarket(address(token), address(0));

        vm.startPrank(seller);
        nft.approve(address(m), tokenId);
        uint256 lid = m.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 days;
        bytes32 structHash = keccak256(abi.encode(_PERMIT_BUY_TYPEHASH, buyer, lid, deadline));
        bytes32 dom = keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("1")),
                block.chainid,
                address(m)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", dom, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);

        vm.startPrank(buyer);
        token.approve(address(m), price * 1e18);
        vm.expectRevert("Whitelist signer not set");
        m.permitBuy(lid, price, deadline, v, r, s);
        vm.stopPrank();
    }

    function test_SetWhitelistSigner() public {
        address newSigner = makeAddr("newSigner");
        market.setWhitelistSigner(newSigner);
        assertEq(market.whitelistSigner(), newSigner);
    }

    // ==================== transferWithCallback（MyTokenV2） ====================

    function test_TransferWithCallback_BuySuccess() public {
        MyTokenV2 t = new MyTokenV2(1_000_000);
        NFTMarket m = new NFTMarket(address(t), signer);
        t.transfer(buyer, 1000);

        vm.startPrank(seller);
        nft.approve(address(m), tokenId);
        uint256 listingId = m.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 days;
        bytes32 structHash = keccak256(abi.encode(_PERMIT_BUY_TYPEHASH, buyer, listingId, deadline));
        bytes32 dom = keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("1")),
                block.chainid,
                address(m)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", dom, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
        bytes memory data = abi.encode(listingId, deadline, v, r, s);

        vm.startPrank(buyer);
        vm.expectEmit(true, true, true, true);
        emit NFTMarket.Sold(listingId, buyer, seller, address(nft), tokenId, price * 1e18);
        t.transferWithCallback(address(m), price, data);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(t.balanceOf(seller), price * 1e18);
        (,,,, bool isActive) = m.listings(listingId);
        assertFalse(isActive);
        vm.stopPrank();
    }

    function test_TransferWithCallback_RefundExcess() public {
        MyTokenV2 t = new MyTokenV2(1_000_000);
        NFTMarket m = new NFTMarket(address(t), signer);
        t.transfer(buyer, 2000);

        vm.startPrank(seller);
        nft.approve(address(m), tokenId);
        uint256 listingId = m.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 overpay = price + 50;
        uint256 deadline = block.timestamp + 1 days;
        bytes32 structHash = keccak256(abi.encode(_PERMIT_BUY_TYPEHASH, buyer, listingId, deadline));
        bytes32 dom = keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("1")),
                block.chainid,
                address(m)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", dom, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
        bytes memory data = abi.encode(listingId, deadline, v, r, s);

        vm.startPrank(buyer);
        uint256 buyerBalanceBefore = t.balanceOf(buyer);
        t.transferWithCallback(address(m), overpay, data);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(t.balanceOf(seller), price * 1e18);
        assertEq(t.balanceOf(buyer), buyerBalanceBefore - overpay * 1e18 + 50 * 1e18);
        vm.stopPrank();
    }

    function test_TransferWithCallback_RevertWhen_InvalidDataDecode() public {
        MyTokenV2 t = new MyTokenV2(1_000_000);
        NFTMarket m = new NFTMarket(address(t), signer);
        t.transfer(buyer, 1000);

        vm.startPrank(seller);
        nft.approve(address(m), tokenId);
        m.list(address(nft), tokenId, price);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert();
        t.transferWithCallback(address(m), price, "");
        vm.stopPrank();
    }

    function test_TransferWithCallback_RevertWhen_InsufficientAmount() public {
        MyTokenV2 t = new MyTokenV2(1_000_000);
        NFTMarket m = new NFTMarket(address(t), signer);
        t.transfer(buyer, 1000);

        vm.startPrank(seller);
        nft.approve(address(m), tokenId);
        uint256 listingId = m.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 days;
        bytes32 structHash = keccak256(abi.encode(_PERMIT_BUY_TYPEHASH, buyer, listingId, deadline));
        bytes32 dom = keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("1")),
                block.chainid,
                address(m)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", dom, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
        bytes memory data = abi.encode(listingId, deadline, v, r, s);

        vm.startPrank(buyer);
        vm.expectRevert("Insufficient amount");
        t.transferWithCallback(address(m), price - 1, data);
        vm.stopPrank();
    }

    // ==================== 不变性测试 ====================

    function test_Invariant_MarketHoldsNoTokens() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(buyer, listingId, deadline);

        vm.startPrank(buyer);
        token.approve(address(market), price * 1e18);
        market.permitBuy(listingId, price, deadline, v, r, s);
        vm.stopPrank();

        assertEq(token.balanceOf(address(market)), 0, "Market should hold no tokens after permitBuy");

        MyTokenV2 t = new MyTokenV2(1_000_000);
        NFTMarket m = new NFTMarket(address(t), signer);
        t.transfer(seller, 1000);

        vm.startPrank(buyer);
        nft.approve(address(m), tokenId);
        listingId = m.list(address(nft), tokenId, price);
        vm.stopPrank();

        deadline = block.timestamp + 1 days;
        bytes32 structHash = keccak256(abi.encode(_PERMIT_BUY_TYPEHASH, seller, listingId, deadline));
        bytes32 dom = keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("1")),
                block.chainid,
                address(m)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", dom, structHash));
        (v, r, s) = vm.sign(SIGNER_PK, digest);
        bytes memory data = abi.encode(listingId, deadline, v, r, s);

        vm.startPrank(seller);
        t.transferWithCallback(address(m), price, data);
        vm.stopPrank();

        assertEq(t.balanceOf(address(m)), 0, "Market should hold no tokens after transferWithCallback");
    }
}
