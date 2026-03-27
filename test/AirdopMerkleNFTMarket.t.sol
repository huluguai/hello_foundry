// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AirdopMerkleNFTMarket} from "../src/v2/mynft/AirdopMerkleNFTMarket.sol";
import {XZXToken} from "../src/v2/mytoken/xzx_token.sol";
import {MyURINFT} from "../src/v2/mynft/MyBasicNFT.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

/**
 * @title AirdopMerkleNFTMarket 测试
 * @notice 覆盖折后购（multicall + permit + Merkle）、原价 buyNFT、multicall 白名单 selector 与 owner 例外等路径。
 * @dev Merkle 叶子与合约一致：`keccak256(abi.encodePacked(account))`；单叶子树时 proof 为空、root 即该叶子。
 */
contract AirdopMerkleNFTMarketTest is Test {
    AirdopMerkleNFTMarket public market;
    XZXToken public token;
    MyURINFT public nft;

    address public seller;
    address public buyer;
    /// @dev 非白名单场景中的购买者（或双叶 Merkle 中的另一叶子）
    address public outsider;

    uint256 internal constant BUYER_PK = 0xA11CE;
    uint256 internal constant OUTSIDER_PK = 0xB0B;

    uint256 public tokenId;
    /// @dev list 时使用的「整币」标价，链上实际价格为 PRICE_WHOLE * 10**decimals
    uint256 public constant PRICE_WHOLE = 100;

    /// @dev 须与 OpenZeppelin ERC20Permit 中 Permit 结构体 typehash 一致
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice 部署 Token/NFT/Market；Market 默认可证明仅 `buyer` 在白名单（单叶子 root）
    function setUp() public {
        seller = makeAddr("seller");
        buyer = vm.addr(BUYER_PK);
        outsider = vm.addr(OUTSIDER_PK);

        token = new XZXToken(1_000_000);
        nft = new MyURINFT();

        bytes32 buyerLeaf = keccak256(abi.encodePacked(buyer));
        market = new AirdopMerkleNFTMarket(address(token), buyerLeaf);

        nft.mint(seller, "ipfs://test-uri-1");
        tokenId = nft.currentTokenId();

        token.transfer(buyer, 1000 * 1e18);
        token.transfer(outsider, 1000 * 1e18);

        vm.label(seller, "seller");
        vm.label(buyer, "buyer");
        vm.label(outsider, "outsider");
        vm.label(address(market), "AirdopMerkleNFTMarket");
        vm.label(address(token), "XZXToken");
        vm.label(address(nft), "MyURINFT");
    }

    // ========== EIP-2612 Permit 辅助（与链上 DOMAIN_SEPARATOR 一致）==========

    /// @dev 构造用户对 Market 合约的 `permit` 所签 EIP-712 digest（\x19\x01 ‖ domain ‖ structHash）
    function _permitDigest(
        address tokenAddr,
        address tokenOwner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, tokenOwner, spender, value, nonce, deadline));
        bytes32 domainSeparator = IERC20Permit(tokenAddr).DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /// @dev 用固定私钥对 `permit` 消息签名，便于 `permitPrePay` 测试
    function _signPermit(address tokenOwner, uint256 pk, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        uint256 nonce = token.nonces(tokenOwner);
        bytes32 digest = _permitDigest(address(token), tokenOwner, address(market), value, nonce, deadline);
        return vm.sign(pk, digest);
    }

    // ========== 折后购（multicall）成功与失败 ==========

    /// @notice 单笔 tx：`permitPrePay` + `claimNFT`，买家付半价 XZX，成交后 listing 关闭、市场不留币
    function test_Multicall_PermitPrePayAndClaim_Success() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, PRICE_WHOLE);
        vm.stopPrank();

        uint256 discount = (PRICE_WHOLE * 1e18) / 2;
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(buyer, BUYER_PK, discount, deadline);

        bytes32[] memory proof = new bytes32[](0);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(AirdopMerkleNFTMarket.permitPrePay, (discount, deadline, v, r, s));
        data[1] = abi.encodeCall(AirdopMerkleNFTMarket.claimNFT, (listingId, proof));

        vm.prank(buyer);
        market.multicall(data);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(token.balanceOf(seller), discount);
        assertEq(token.balanceOf(address(market)), 0);
        (,,,, bool active) = market.listings(listingId);
        assertFalse(active);
        assertEq(market.prepaidAmount(buyer), 0);
    }

    /// @notice 非 multicall 直接调 `claimNFT` 应被拒绝（须 `_inMulticall`）
    function test_ClaimNFT_RevertWhen_NotViaMulticall() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, PRICE_WHOLE);
        vm.stopPrank();

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(buyer);
        vm.expectRevert(AirdopMerkleNFTMarket.ClaimMustBeViaMulticall.selector);
        market.claimNFT(listingId, proof);
    }

    /// @notice root 仅含 buyer 叶子时，outsider 即使完成 permit 也无法通过 Merkle 校验
    function test_ClaimNFT_RevertWhen_NotWhitelisted() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, PRICE_WHOLE);
        vm.stopPrank();

        uint256 discount = (PRICE_WHOLE * 1e18) / 2;
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(outsider, OUTSIDER_PK, discount, deadline);

        bytes32[] memory proof = new bytes32[](0);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(AirdopMerkleNFTMarket.permitPrePay, (discount, deadline, v, r, s));
        data[1] = abi.encodeCall(AirdopMerkleNFTMarket.claimNFT, (listingId, proof));

        vm.prank(outsider);
        vm.expectRevert(AirdopMerkleNFTMarket.NotWhitelisted.selector);
        market.multicall(data);
    }

    /// @notice `permitPrePay` 记账值小于折后应付wei时，`claimNFT` 应 InsufficientPrepaid
    function test_ClaimNFT_RevertWhen_InsufficientPrepaid() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, PRICE_WHOLE);
        vm.stopPrank();

        uint256 discount = (PRICE_WHOLE * 1e18) / 2;
        uint256 tooSmall = discount - 1;
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(buyer, BUYER_PK, tooSmall, deadline);

        bytes32[] memory proof = new bytes32[](0);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(AirdopMerkleNFTMarket.permitPrePay, (tooSmall, deadline, v, r, s));
        data[1] = abi.encodeCall(AirdopMerkleNFTMarket.claimNFT, (listingId, proof));

        vm.prank(buyer);
        vm.expectRevert(AirdopMerkleNFTMarket.InsufficientPrepaid.selector);
        market.multicall(data);
    }

    /// @notice permit deadline 已过；首步 `permit` 即失败，整笔 multicall revert
    function test_PermitPrePay_RevertWhen_PermitExpired() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, PRICE_WHOLE);
        vm.stopPrank();

        uint256 discount = (PRICE_WHOLE * 1e18) / 2;
        uint256 deadline = block.timestamp + 100;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(buyer, BUYER_PK, discount, deadline);

        vm.warp(block.timestamp + 101);

        bytes32[] memory proof = new bytes32[](0);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(AirdopMerkleNFTMarket.permitPrePay, (discount, deadline, v, r, s));
        data[1] = abi.encodeCall(AirdopMerkleNFTMarket.claimNFT, (uint256(0), proof));

        vm.prank(buyer);
        vm.expectRevert();
        market.multicall(data);
    }

    /// @notice 双叶子 Merkle（OZ commutativeKeccak256）：outsider 用 sibling proof 证明包含关系并成交
    function test_Multicall_TwoLeafMerkle_ProofWorks() public {
        bytes32 lBuyer = keccak256(abi.encodePacked(buyer));
        bytes32 lOut = keccak256(abi.encodePacked(outsider));
        bytes32 root = Hashes.commutativeKeccak256(lBuyer, lOut);
        market = new AirdopMerkleNFTMarket(address(token), root);

        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, PRICE_WHOLE);
        vm.stopPrank();

        uint256 discount = (PRICE_WHOLE * 1e18) / 2;
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(outsider, OUTSIDER_PK, discount, deadline);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = lBuyer;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(AirdopMerkleNFTMarket.permitPrePay, (discount, deadline, v, r, s));
        data[1] = abi.encodeCall(AirdopMerkleNFTMarket.claimNFT, (listingId, proof));

        vm.prank(outsider);
        market.multicall(data);

        assertEq(nft.ownerOf(tokenId), outsider);
        assertEq(token.balanceOf(seller), discount);
    }

    /// @notice 上架后 NFT 已转离卖家，`claimNFT` 应 NFTNoLongerForSale
    function test_ClaimNFT_RevertWhen_NFTNotWithSeller() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, PRICE_WHOLE);
        nft.transferFrom(seller, buyer, tokenId);
        vm.stopPrank();

        uint256 discount = (PRICE_WHOLE * 1e18) / 2;
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(buyer, BUYER_PK, discount, deadline);

        bytes32[] memory proof = new bytes32[](0);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(AirdopMerkleNFTMarket.permitPrePay, (discount, deadline, v, r, s));
        data[1] = abi.encodeCall(AirdopMerkleNFTMarket.claimNFT, (listingId, proof));

        vm.prank(buyer);
        vm.expectRevert(AirdopMerkleNFTMarket.NFTNoLongerForSale.selector);
        market.multicall(data);
    }

    // ========== 原价 buyNFT ==========

    /// @notice 非白名单路径：outsider `approve` 后全价购买
    function test_BuyNFT_FullPrice_Success() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, PRICE_WHOLE);
        vm.stopPrank();

        uint256 full = PRICE_WHOLE * 1e18;

        vm.startPrank(outsider);
        token.approve(address(market), full);
        market.buyNFT(listingId, PRICE_WHOLE);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), outsider);
        assertEq(token.balanceOf(seller), full);
        assertEq(token.balanceOf(address(market)), 0);
    }

    /// @notice 支付整币单位不足 listing 标价时 revert
    function test_BuyNFT_RevertWhen_InsufficientAmount() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, PRICE_WHOLE);
        vm.stopPrank();

        vm.startPrank(outsider);
        token.approve(address(market), PRICE_WHOLE * 1e18);
        vm.expectRevert(AirdopMerkleNFTMarket.InsufficientAmount.selector);
        market.buyNFT(listingId, PRICE_WHOLE - 1);
        vm.stopPrank();
    }

    // ========== multicall 安全：重入与 selector 白名单 ==========

    /**
     * @notice 外层 multicall 已置 `_inMulticall` 时再 delegatecall 进入内层 multicall，应 MulticallReentrant
     * @dev 必须由合约 owner（本测试为 Test 合约）发起，否则内层 calldata 含 `multicall` selector 会被非 owner 白名单拦截
     */
    function test_Multicall_RevertWhen_Reentrant() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.list(address(nft), tokenId, PRICE_WHOLE);
        vm.stopPrank();

        bytes[] memory inner = new bytes[](1);
        inner[0] = abi.encodeCall(AirdopMerkleNFTMarket.multicall, new bytes[](0));

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(AirdopMerkleNFTMarket.multicall, inner);

        vm.expectRevert(AirdopMerkleNFTMarket.MulticallReentrant.selector);
        market.multicall(data);
    }

    /// @notice 普通用户 multicall 仅允许 permitPrePay / claimNFT；编入 buyNFT 应 InvalidMulticallSelector
    function test_Multicall_RevertWhen_InvalidSelector() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        uint256 listingId = market.list(address(nft), tokenId, PRICE_WHOLE);
        vm.stopPrank();

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(AirdopMerkleNFTMarket.buyNFT, (listingId, PRICE_WHOLE));

        vm.prank(buyer);
        vm.expectRevert(AirdopMerkleNFTMarket.InvalidMulticallSelector.selector);
        market.multicall(data);
    }

    /// @notice 子 calldata 长度不足 4 字节，无法解析 selector
    function test_Multicall_RevertWhen_EntryTooShort() public {
        bytes[] memory data = new bytes[](1);
        data[0] = hex"010203";

        vm.prank(buyer);
        vm.expectRevert(AirdopMerkleNFTMarket.InvalidMulticallSelector.selector);
        market.multicall(data);
    }

    /// @notice owner 跳过 selector 限制，可通过 multicall 调用 `setMerkleRoot`
    function test_Owner_Multicall_AllowsNonWhitelistedSelector() public {
        bytes32 newRoot = bytes32(uint256(123));
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(AirdopMerkleNFTMarket.setMerkleRoot, (newRoot));

        market.multicall(data);

        assertEq(market.merkleRoot(), newRoot);
    }
}
