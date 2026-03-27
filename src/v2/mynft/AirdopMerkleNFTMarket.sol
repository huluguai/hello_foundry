// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title AirdopMerkleNFTMarket
 * @notice 支持两种买法：（1）白名单 + EIP-2612 Permit + multicall 半折；（2）任意人原价 `buyNFT`。
 *
 * **典型折后购一笔 tx**：用户调 `multicall([permitPrePay, claimNFT])`
 * - `permitPrePay`：在支付代币上把本市场合约设为 spender，并把 `prepaidAmount[msg.sender]` 记为与 permit 相同的 `value`。
 * - `claimNFT`：校验 Merkle 白名单，从买家转 **折后** Token 给卖家，把 NFT 从卖家转给买家；仅当 `_inMulticall` 为真时可进（禁止单独外链 claim）。
 *
 * @dev 白名单叶子必须与链下建树一致：`leaf = keccak256(abi.encodePacked(用户地址))`，证明用 OpenZeppelin `MerkleProof`（与 `Hashes.commutativeKeccak256` 建树兼容）。
 * @dev `multicall` 对 **非 owner** 调用方：每条子 calldata 只能是 `permitPrePay` 或 `claimNFT` 的编码，防止借 delegatecall 乱调其它函数；**owner** 不受限（便于治理），须保管好私钥。
 * @dev 折扣：`discountPrice = priceInWei * discountBps / 10000`，默认 `discountBps = 5000` 即 50%。
 * @dev 市价不托管 ERC20：成交后 Token 直接进卖家，本合约余额应为 0。
 */
contract AirdopMerkleNFTMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice 唯一支付代币（需 `decimals()` + EIP-2612 `permit`，如 XZXToken）
    IERC20 public immutable token;
    /// @dev `10 ** token.decimals()`，与 `list` 入参「整币价格」相乘得到链上 `priceInWei`
    uint256 private immutable tokenUnit;

    /// @notice Merkle 根；叶子为 `keccak256(abi.encodePacked(account))`
    bytes32 public merkleRoot;
    /// @notice 折扣基点：10000 = 100%，默认 5000 = 付标价的一半（向下取整到 wei）
    uint16 public discountBps;

    /**
     * @notice `permitPrePay` 写入的「本合约认为你可用于 claim 的额度」
     * @dev 与链上 ERC20 `allowance` 并行：`claim` 时会 `transferFrom`，两者都需足够；claim 成功会扣减本 mapping。
     */
    mapping(address => uint256) public prepaidAmount;

    /// @dev `multicall` 执行 delegatecall 子调用期间为 true，供 `onlyMulticall` 判断
    bool private _inMulticall;

    /// @dev 非 owner 的 multicall 子调用仅允许这两类函数（与编译产物 `cast sig` 一致）
    bytes4 private constant SELECTOR_PERMIT_PRE_PAY = 0xb7bebb5e;
    bytes4 private constant SELECTOR_CLAIM_NFT = 0x765b1845;

    /// @notice 单条挂单：`seller` 为挂单时 NFT 的 owner；NFT 不存入本合约，仅靠卖家事先 `approve` / `setApprovalForAll` 给市场
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 priceInWei;
        bool isActive;
    }

    mapping(uint256 => Listing) public listings;
    uint256 public nextListingId;
    /// @dev `keccak256(abi.encode(nftContract, tokenId)) -> listingId + 1`（0 表示无）；用于防同一 NFT 重复活跃上架
    mapping(bytes32 => uint256) public activeListingByNft;

    event Listed(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 priceInWei);
    event Unlisted(uint256 indexed listingId, address indexed seller);
    event Sold(uint256 indexed listingId, address indexed buyer, address indexed seller, address nftContract, uint256 tokenId, uint256 priceInWei);
    event SoldWithDiscount(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 discountPriceInWei,
        uint256 fullPriceInWei
    );
    event MerkleRootUpdated(bytes32 indexed newRoot);
    event DiscountBpsUpdated(uint16 newDiscountBps);

    error InvalidTokenAddress();
    error InvalidNFTContract();
    error PriceMustBePositive();
    error NotOwnerNorApproved();
    error AlreadyListed();
    error NotListed();
    error NotLister();
    error InsufficientAmount();
    error NFTNoLongerForSale();
    error ClaimMustBeViaMulticall();
    error NotWhitelisted();
    error InsufficientPrepaid();
    error InvalidDiscountBps();
    error MulticallReentrant();
    error InvalidMulticallSelector();

    /// @dev 仅允许在 `multicall` 开启的上下文中进入（delegatecall 栈内 `msg.sender` 仍为买家 EOA）
    modifier onlyMulticall() {
        if (!_inMulticall) revert ClaimMustBeViaMulticall();
        _;
    }

    /// @param _tokenAddress 支付 Token 地址（不可为 0）
    /// @param initialMerkleRoot 初始 Merkle 根；单地址树可为该地址的 leaf
    constructor(address _tokenAddress, bytes32 initialMerkleRoot) Ownable(msg.sender) {
        if (_tokenAddress == address(0)) revert InvalidTokenAddress();
        token = IERC20(_tokenAddress);
        uint256 unit;
        unchecked {
            unit = 10 ** uint256(IERC20Metadata(_tokenAddress).decimals());
        }
        tokenUnit = unit;
        merkleRoot = initialMerkleRoot;
        discountBps = 5000;
        emit MerkleRootUpdated(initialMerkleRoot);
        emit DiscountBpsUpdated(discountBps);
    }

    /// @notice 更新白名单根（仅 owner）
    function setMerkleRoot(bytes32 newRoot) external onlyOwner {
        merkleRoot = newRoot;
        emit MerkleRootUpdated(newRoot);
    }

    /// @notice 更新折扣比例（仅 owner；`newBps` 最大 10000）
    function setDiscountBps(uint16 newBps) external onlyOwner {
        if (newBps > 10_000) revert InvalidDiscountBps();
        discountBps = newBps;
        emit DiscountBpsUpdated(newBps);
    }

    /**
     * @notice 按顺序对 `data` 中每一项做 **本合约自身** 的 `delegatecall`
     * @dev 效果：复用本合约代码与存储，`msg.sender` 不变（始终是发起交易的地址）。
     *      常见写法：`data = [ abi.encodeCall(permitPrePay, ...), abi.encodeCall(claimNFT, ...) ]`。
     * @dev 子调用失败会带上原 revert data 整笔回滚（含已成功子步的状态，整 tx 回滚）。
     */
    function multicall(bytes[] calldata data) external {
        if (_inMulticall) revert MulticallReentrant();
        uint256 n = data.length;
        // 普通用户：子调用只能是 permit / claim，避免在 _inMulticall 期间编排任意 external
        if (msg.sender != owner()) {
            for (uint256 i = 0; i < n;) {
                _requireAllowedUserMulticallSelector(data[i]);
                unchecked {
                    ++i;
                }
            }
        }
        _inMulticall = true;
        for (uint256 i = 0; i < n;) {
            (bool success, bytes memory returndata) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(returndata, 0x20), mload(returndata))
                }
            }
            unchecked {
                ++i;
            }
        }
        _inMulticall = false;
    }

    /// @dev 解析 `data[i]` 前 4 字节为函数选择器，须为常数中登记的两枚之一
    function _requireAllowedUserMulticallSelector(bytes calldata entry) private pure {
        if (entry.length < 4) revert InvalidMulticallSelector();
        bytes4 sel = bytes4(entry[0:4]);
        if (sel != SELECTOR_PERMIT_PRE_PAY && sel != SELECTOR_CLAIM_NFT) {
            revert InvalidMulticallSelector();
        }
    }

    /**
     * @notice EIP-2612：授权本合约为 token spender，并把「预付记账」设为 `value`
     * @dev 典型放在 multicall 第一项；`value` 建议 ≥ 当次 `claimNFT` 需要的折后 wei。
     */
    function permitPrePay(uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        IERC20Permit(address(token)).permit(msg.sender, address(this), value, deadline, v, r, s);
        prepaidAmount[msg.sender] = value;
    }

    /**
     * @notice 白名单折后购买（必须在 multicall 内调用）
     * @param listingId `list` 返回的 id
     * @param proof 证明 `keccak256(abi.encodePacked(msg.sender))` 在 `merkleRoot` 下成立；单叶子时可传空数组
     *
     * @dev 顺序为 **Checks - Effects - Interactions**：先改 `prepaidAmount`、下架，再转 Token / NFT，降低重入时状态不一致风险；并配 `nonReentrant`。
     */
    function claimNFT(uint256 listingId, bytes32[] calldata proof) external onlyMulticall nonReentrant {
        address buyer = msg.sender;
        bytes32 leaf = keccak256(abi.encodePacked(buyer));
        if (!MerkleProof.verifyCalldata(proof, merkleRoot, leaf)) revert NotWhitelisted();

        Listing storage l = listings[listingId];
        if (!l.isActive) revert NotListed();

        IERC721 nftContract = IERC721(l.nftContract);
        if (nftContract.ownerOf(l.tokenId) != l.seller) revert NFTNoLongerForSale();

        uint256 fullPrice = l.priceInWei;
        uint256 discountPrice = (fullPrice * uint256(discountBps)) / 10_000;
        if (discountPrice == 0) revert InsufficientAmount();

        uint256 prepaid = prepaidAmount[buyer];
        if (prepaid < discountPrice) revert InsufficientPrepaid();

        // 缓存存储指针，避免先删 listing 后读不到卖家/NFT 参数
        address sellerAddr = l.seller;
        address nftAddr = l.nftContract;
        uint256 tid = l.tokenId;
        bytes32 nftKey = keccak256(abi.encode(nftAddr, tid));

        // Effects：扣预付、关单（再转帐）
        unchecked {
            prepaidAmount[buyer] = prepaid - discountPrice;
        }
        l.isActive = false;
        delete activeListingByNft[nftKey];

        // Interactions：代币与 NFT 转移
        token.safeTransferFrom(buyer, sellerAddr, discountPrice);
        nftContract.transferFrom(sellerAddr, buyer, tid);

        emit SoldWithDiscount(listingId, buyer, sellerAddr, nftAddr, tid, discountPrice, fullPrice);
    }

    /**
     * @notice 上架：`price` 为 **整币单位**（与 `token.decimals()` 相乘后写入 `priceInWei`）
     * @dev 记录的 `seller` 为当前 `ownerOf(tokenId)`（若经授权代挂，仍为 NFT 持有人，非 msg.sender）
     */
    function list(address _nftContract, uint256 _tokenId, uint256 _price) external returns (uint256) {
        if (_nftContract == address(0)) revert InvalidNFTContract();
        if (_price == 0) revert PriceMustBePositive();

        IERC721 nft = IERC721(_nftContract);
        address owner = nft.ownerOf(_tokenId);
        if (!(owner == msg.sender || nft.isApprovedForAll(owner, msg.sender) || nft.getApproved(_tokenId) == msg.sender)) {
            revert NotOwnerNorApproved();
        }

        bytes32 key = keccak256(abi.encode(_nftContract, _tokenId));
        uint256 existingId = activeListingByNft[key];
        if (existingId != 0 && listings[existingId - 1].isActive) {
            revert AlreadyListed();
        }

        uint256 priceInWei = _price * tokenUnit;
        uint256 listingId = nextListingId;
        unchecked {
            nextListingId = listingId + 1;
        }

        listings[listingId] = Listing({seller: owner, nftContract: _nftContract, tokenId: _tokenId, priceInWei: priceInWei, isActive: true});
        activeListingByNft[key] = listingId + 1;

        emit Listed(listingId, owner, _nftContract, _tokenId, priceInWei);
        return listingId;
    }

    /// @notice 下架：仅挂单记录的 `seller` 可撤
    function unlist(uint256 _listingId) external {
        Listing storage l = listings[_listingId];
        if (!l.isActive) revert NotListed();
        if (l.seller != msg.sender) revert NotLister();

        l.isActive = false;
        bytes32 nftKey = keccak256(abi.encode(l.nftContract, l.tokenId));
        delete activeListingByNft[nftKey];

        emit Unlisted(_listingId, msg.sender);
    }

    /**
     * @notice 原价购买（不走 Merkle / multicall）
     * @param amountTokenUnits 支付整币数量，须 ≥ listing 标价对应的整币数（多付不会自动找零，勿多付）
     */
    function buyNFT(uint256 listingId, uint256 amountTokenUnits) external nonReentrant {
        _executePurchaseFullPrice(msg.sender, listingId, amountTokenUnits);
    }

    /// @notice 查询某单的标价（整币单位，向下取整）
    function getPriceInTokenUnits(uint256 _listingId) external view returns (uint256) {
        return listings[_listingId].priceInWei / tokenUnit;
    }

    /// @dev 与 `claimNFT` 相同 CEI：先关单再转账
    function _executePurchaseFullPrice(address buyer, uint256 listingId, uint256 amountTokenUnits) internal {
        Listing storage l = listings[listingId];
        if (!l.isActive) revert NotListed();

        IERC721 nft = IERC721(l.nftContract);
        if (nft.ownerOf(l.tokenId) != l.seller) revert NFTNoLongerForSale();

        uint256 amountInWei = amountTokenUnits * tokenUnit;
        if (amountInWei < l.priceInWei) revert InsufficientAmount();

        address sellerAddr = l.seller;
        address nftAddr = l.nftContract;
        uint256 tid = l.tokenId;
        uint256 priceInWei = l.priceInWei;
        bytes32 nftKey = keccak256(abi.encode(nftAddr, tid));

        l.isActive = false;
        delete activeListingByNft[nftKey];

        token.safeTransferFrom(buyer, sellerAddr, priceInWei);
        nft.transferFrom(sellerAddr, buyer, tid);

        emit Sold(listingId, buyer, sellerAddr, nftAddr, tid, priceInWei);
    }
}
