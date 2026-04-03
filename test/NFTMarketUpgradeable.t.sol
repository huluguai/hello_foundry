// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NFTMarketUpgradeableV1} from "../src/v2/mynft/upgradeable/NFTMarketUpgradeableV1.sol";
import {NFTMarketUpgradeableV2} from "../src/v2/mynft/upgradeable/NFTMarketUpgradeableV2.sol";
import {XZXToken} from "../src/v2/mytoken/xzx_token.sol";
import {MyTokenV2} from "../src/v2/mytoken/my_token_v2.sol";
import {MyURINFT} from "../src/v2/mynft/MyBasicNFT.sol";

contract NFTMarketUpgradeableTest is Test {
    NFTMarketUpgradeableV1 internal marketProxyV1;
    NFTMarketUpgradeableV2 internal market;
    XZXToken internal token;
    MyURINFT internal nft;

    address internal seller;
    address internal buyer;
    uint256 internal constant SELLER_PK = 0xBEEF;
    uint256 internal constant SIGNER_PK = 0xA11CE;
    address internal signer;

    uint256 internal tokenId = 1;
    uint256 internal price = 100;

    bytes32 internal constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant _PERMIT_BUY_TYPEHASH =
        keccak256("PermitBuy(address buyer,uint256 listingId,uint256 deadline)");
    bytes32 internal constant _PERMIT_LIST_TYPEHASH =
        keccak256("PermitList(address seller,address nftContract,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)");

    function setUp() public {
        seller = vm.addr(SELLER_PK);
        buyer = makeAddr("buyer");
        signer = vm.addr(SIGNER_PK);

        token = new XZXToken(1_000_000);
        nft = new MyURINFT();

        NFTMarketUpgradeableV1 impl = new NFTMarketUpgradeableV1();
        bytes memory init = abi.encodeCall(NFTMarketUpgradeableV1.initialize, (address(token), signer, address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);
        marketProxyV1 = NFTMarketUpgradeableV1(address(proxy));
        market = NFTMarketUpgradeableV2(address(proxy));

        nft.mint(seller, "ipfs://test-uri-1");
        tokenId = nft.currentTokenId();

        token.transfer(buyer, 1000 * 1e18);
    }

    function _domainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("1")),
                block.chainid,
                verifyingContract
            )
        );
    }

    function _permitBuyDigest(address verifyingContract, address buyer_, uint256 listingId, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(_PERMIT_BUY_TYPEHASH, buyer_, listingId, deadline));
        return keccak256(abi.encodePacked(hex"1901", _domainSeparator(verifyingContract), structHash));
    }

    function _permitListDigest(
        address verifyingContract,
        address seller_,
        address nft_,
        uint256 tid,
        uint256 price_,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(_PERMIT_LIST_TYPEHASH, seller_, nft_, tid, price_, nonce, deadline));
        return keccak256(abi.encodePacked(hex"1901", _domainSeparator(verifyingContract), structHash));
    }

    function _upgradeToV2() internal {
        NFTMarketUpgradeableV2 impl = new NFTMarketUpgradeableV2();
        marketProxyV1.upgradeToAndCall(address(impl), "");
    }

    function test_List_OnProxy_Success() public {
        vm.startPrank(seller);
        nft.approve(address(marketProxyV1), tokenId);
        uint256 listingId = marketProxyV1.list(address(nft), tokenId, price);
        assertEq(listingId, 0);
        vm.stopPrank();
    }

    function test_PermitBuy_OnProxy_Success() public {
        vm.startPrank(seller);
        nft.approve(address(marketProxyV1), tokenId);
        uint256 listingId = marketProxyV1.list(address(nft), tokenId, price);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _permitBuyDigest(address(marketProxyV1), buyer, listingId, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);

        vm.startPrank(buyer);
        token.approve(address(marketProxyV1), price * 1e18);
        marketProxyV1.permitBuy(listingId, price, deadline, v, r, s);
        assertEq(nft.ownerOf(tokenId), buyer);
        vm.stopPrank();
    }

    function test_Upgrade_ToV2_PreserveListings() public {
        vm.startPrank(seller);
        nft.approve(address(marketProxyV1), tokenId);
        uint256 listingId = marketProxyV1.list(address(nft), tokenId, price);
        vm.stopPrank();

        _upgradeToV2();

        (address listedSeller,, uint256 listedTokenId, uint256 listedPriceInWei, bool isActive) = market.listings(listingId);
        assertEq(listedSeller, seller);
        assertEq(listedTokenId, tokenId);
        assertEq(listedPriceInWei, price * 1e18);
        assertTrue(isActive);
    }

    function test_ListWithSig_AfterUpgrade() public {
        _upgradeToV2();

        vm.startPrank(seller);
        nft.setApprovalForAll(address(market), true);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = 0;
        bytes32 digest = _permitListDigest(address(market), seller, address(nft), tokenId, price, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SELLER_PK, digest);

        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        uint256 listingId = market.listWithSig(seller, address(nft), tokenId, price, nonce, deadline, v, r, s);

        (address listedSeller,,,, bool isActive) = market.listings(listingId);
        assertEq(listedSeller, seller);
        assertTrue(isActive);
        assertEq(market.listingNonces(seller), 1);

        uint256 deadlineBuy = block.timestamp + 1 days;
        bytes32 buyDigest = _permitBuyDigest(address(market), buyer, listingId, deadlineBuy);
        (v, r, s) = vm.sign(SIGNER_PK, buyDigest);

        vm.startPrank(buyer);
        token.approve(address(market), price * 1e18);
        market.permitBuy(listingId, price, deadlineBuy, v, r, s);
        assertEq(nft.ownerOf(tokenId), buyer);
        vm.stopPrank();
    }

    function test_ListWithSig_RevertWhen_WrongNonce() public {
        _upgradeToV2();
        vm.prank(seller);
        nft.setApprovalForAll(address(market), true);

        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _permitListDigest(address(market), seller, address(nft), tokenId, price, 1, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SELLER_PK, digest);

        vm.expectRevert(NFTMarketUpgradeableV2.InvalidListingNonce.selector);
        market.listWithSig(seller, address(nft), tokenId, price, 1, deadline, v, r, s);
    }

    function test_TransferWithCallback_OnProxy_AfterV2() public {
        (MyTokenV2 t, NFTMarketUpgradeableV2 m2) = _deployMarketWithTokenV2();
        t.transfer(buyer, 1000);

        vm.startPrank(seller);
        nft.setApprovalForAll(address(m2), true);
        uint256 deadlineL = block.timestamp + 1 days;
        bytes32 dList = _permitListDigest(address(m2), seller, address(nft), tokenId, price, 0, deadlineL);
        (uint8 v0, bytes32 r0, bytes32 s0) = vm.sign(SELLER_PK, dList);
        uint256 listingId = m2.listWithSig(seller, address(nft), tokenId, price, 0, deadlineL, v0, r0, s0);
        vm.stopPrank();

        bytes memory data = _encodePermitBuyData(address(m2), listingId);
        vm.prank(buyer);
        t.transferWithCallback(address(m2), price, data);
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function _deployMarketWithTokenV2() internal returns (MyTokenV2 t, NFTMarketUpgradeableV2 m2) {
        t = new MyTokenV2(1_000_000);
        NFTMarketUpgradeableV1 impl = new NFTMarketUpgradeableV1();
        bytes memory init = abi.encodeCall(NFTMarketUpgradeableV1.initialize, (address(t), signer, address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);
        NFTMarketUpgradeableV1(address(proxy)).upgradeToAndCall(address(new NFTMarketUpgradeableV2()), "");
        m2 = NFTMarketUpgradeableV2(address(proxy));
    }

    function _encodePermitBuyData(address verifyingContract, uint256 listingId) internal view returns (bytes memory) {
        uint256 deadlineBuy = block.timestamp + 1 days;
        bytes32 digest = _permitBuyDigest(verifyingContract, buyer, listingId, deadlineBuy);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
        return abi.encode(listingId, deadlineBuy, v, r, s);
    }
}

