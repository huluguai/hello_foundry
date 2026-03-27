// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ITokenRecipient} from "../mytoken/ITokenRecipient.sol";

/**
 * @title NFTMarket - ERC20 支付 + EIP-712 白名单购买 NFT
 * @dev list / unlist；购买仅允许 permitBuy 或 transferWithCallback→tokensReceived（data 含签名）
 */
contract NFTMarket is Ownable, EIP712, ITokenRecipient {
    using SafeERC20 for IERC20;

    bytes32 private constant PERMIT_BUY_TYPEHASH =
        keccak256("PermitBuy(address buyer,uint256 listingId,uint256 deadline)");

    IERC20 public immutable token;
    /// @dev 10 ** token.decimals()，避免每次 list / 购买重复幂运算
    uint256 private immutable tokenUnit;

    address public whitelistSigner;

    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 priceInWei;
        bool isActive;
    }

    mapping(uint256 => Listing) public listings;
    uint256 public nextListingId;
    mapping(bytes32 => uint256) public activeListingByNft;

    event Listed(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 priceInWei);
    event Unlisted(uint256 indexed listingId, address indexed seller);
    event Sold(uint256 indexed listingId, address indexed buyer, address indexed seller, address nftContract, uint256 tokenId, uint256 priceInWei);
    event WhitelistSignerUpdated(address indexed newSigner);

    error BuyNFTDisabled();
    error InvalidTokenAddress();
    error InvalidNFTContract();
    error PriceMustBePositive();
    error NotOwnerNorApproved();
    error AlreadyListed();
    error NotListed();
    error NotLister();
    error OnlyPaymentToken();
    error TokensMustBeSentToMarket();
    error WhitelistSignerNotSet();
    error PermitExpired();
    error InvalidPermitSignature();
    error InsufficientAmount();
    error NFTNoLongerForSale();

    constructor(address _tokenAddress, address initialWhitelistSigner) Ownable(msg.sender) EIP712("NFTMarket", "1") {
        if (_tokenAddress == address(0)) revert InvalidTokenAddress();
        token = IERC20(_tokenAddress);
        uint256 unit;
        unchecked {
            unit = 10 ** uint256(IERC20Metadata(_tokenAddress).decimals());
        }
        tokenUnit = unit;
        whitelistSigner = initialWhitelistSigner;
    }

    function setWhitelistSigner(address newSigner) external onlyOwner {
        whitelistSigner = newSigner;
        emit WhitelistSignerUpdated(newSigner);
    }

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

    function unlist(uint256 _listingId) external {
        Listing storage l = listings[_listingId];
        if (!l.isActive) revert NotListed();
        if (l.seller != msg.sender) revert NotLister();

        l.isActive = false;
        bytes32 nftKey = keccak256(abi.encode(l.nftContract, l.tokenId));
        delete activeListingByNft[nftKey];

        emit Unlisted(_listingId, msg.sender);
    }

    /// @notice 已禁用；请使用带白名单签名的 permitBuy
    function buyNFT(uint256, uint256) external pure {
        revert BuyNFTDisabled();
    }

    /**
     * @notice 白名单用户：项目方 EIP-712 签名 PermitBuy 后，approve token 再调用
     * @param _amount 支付代币数量（整币单位，与 list 时一致）
     */
    function permitBuy(uint256 listingId, uint256 _amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        _verifyPermitBuy(msg.sender, listingId, deadline, v, r, s);
        _executePurchaseDirect(msg.sender, listingId, _amount);
    }

    /**
     * @notice transferWithCallback 回调；data = abi.encode(listingId, deadline, v, r, s)
     */
    function tokensReceived(address from, address to, uint256 amount, bytes calldata data) external returns (bool) {
        if (msg.sender != address(token)) revert OnlyPaymentToken();
        if (to != address(this)) revert TokensMustBeSentToMarket();

        (uint256 listingId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi.decode(data, (uint256, uint256, uint8, bytes32, bytes32));
        _verifyPermitBuy(from, listingId, deadline, v, r, s);
        _executePurchaseCallback(from, listingId, amount);

        return true;
    }

    function getPriceInTokenUnits(uint256 _listingId) external view returns (uint256) {
        return listings[_listingId].priceInWei / tokenUnit;
    }

    function _verifyPermitBuy(address buyer, uint256 listingId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) internal view {
        if (whitelistSigner == address(0)) revert WhitelistSignerNotSet();
        if (block.timestamp > deadline) revert PermitExpired();
        bytes32 structHash = keccak256(abi.encode(PERMIT_BUY_TYPEHASH, buyer, listingId, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        if (ECDSA.recover(digest, v, r, s) != whitelistSigner) {
            revert InvalidPermitSignature();
        }
    }

    function _executePurchaseDirect(address buyer, uint256 listingId, uint256 amountTokenUnits) internal {
        Listing storage l = listings[listingId];
        if (!l.isActive) revert NotListed();

        IERC721 nft = IERC721(l.nftContract);
        if (nft.ownerOf(l.tokenId) != l.seller) revert NFTNoLongerForSale();

        uint256 amountInWei = amountTokenUnits * tokenUnit;
        if (amountInWei < l.priceInWei) revert InsufficientAmount();

        bytes32 nftKey = keccak256(abi.encode(l.nftContract, l.tokenId));

        token.safeTransferFrom(buyer, l.seller, l.priceInWei);
        nft.transferFrom(l.seller, buyer, l.tokenId);

        l.isActive = false;
        delete activeListingByNft[nftKey];

        emit Sold(listingId, buyer, l.seller, l.nftContract, l.tokenId, l.priceInWei);
    }

    function _executePurchaseCallback(address buyer, uint256 listingId, uint256 amountWei) internal {
        Listing storage l = listings[listingId];
        if (!l.isActive) revert NotListed();

        IERC721 nft = IERC721(l.nftContract);
        if (nft.ownerOf(l.tokenId) != l.seller) revert NFTNoLongerForSale();
        if (amountWei < l.priceInWei) revert InsufficientAmount();

        uint256 priceInWei = l.priceInWei;
        bytes32 nftKey = keccak256(abi.encode(l.nftContract, l.tokenId));
        uint256 priceInTokenUnits = priceInWei / tokenUnit;
        token.safeTransfer(l.seller, priceInTokenUnits);

        if (amountWei > priceInWei) {
            uint256 refundInTokenUnits = (amountWei - priceInWei) / tokenUnit;
            if (refundInTokenUnits > 0) {
                token.safeTransfer(buyer, refundInTokenUnits);
            }
        }

        nft.transferFrom(l.seller, buyer, l.tokenId);

        l.isActive = false;
        delete activeListingByNft[nftKey];

        emit Sold(listingId, buyer, l.seller, l.nftContract, l.tokenId, priceInWei);
    }
}
