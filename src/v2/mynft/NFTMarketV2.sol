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
    uint8 private immutable _decimals;

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

    constructor(address _tokenAddress, address initialWhitelistSigner) Ownable(msg.sender) EIP712("NFTMarket", "1") {
        require(_tokenAddress != address(0), "Invalid token address");
        token = IERC20(_tokenAddress);
        _decimals = IERC20Metadata(_tokenAddress).decimals();
        whitelistSigner = initialWhitelistSigner;
    }

    function setWhitelistSigner(address newSigner) external onlyOwner {
        whitelistSigner = newSigner;
        emit WhitelistSignerUpdated(newSigner);
    }

    function list(address _nftContract, uint256 _tokenId, uint256 _price) external returns (uint256) {
        require(_nftContract != address(0), "Invalid NFT contract");
        require(_price > 0, "Price must be > 0");

        IERC721 nft = IERC721(_nftContract);
        address owner = nft.ownerOf(_tokenId);
        require(
            owner == msg.sender || nft.isApprovedForAll(owner, msg.sender) || nft.getApproved(_tokenId) == msg.sender,
            "Not owner nor approved"
        );

        bytes32 key = keccak256(abi.encode(_nftContract, _tokenId));
        uint256 existingId = activeListingByNft[key];
        require(existingId == 0 || !listings[existingId - 1].isActive, "Already listed");

        uint256 priceInWei = _price * (10 ** uint256(_decimals));
        uint256 listingId = nextListingId++;

        listings[listingId] = Listing({seller: owner, nftContract: _nftContract, tokenId: _tokenId, priceInWei: priceInWei, isActive: true});
        activeListingByNft[key] = listingId + 1;

        emit Listed(listingId, owner, _nftContract, _tokenId, priceInWei);
        return listingId;
    }

    function unlist(uint256 _listingId) external {
        Listing storage l = listings[_listingId];
        require(l.isActive, "Not listed");
        require(l.seller == msg.sender, "Not lister");

        l.isActive = false;
        delete activeListingByNft[keccak256(abi.encode(l.nftContract, l.tokenId))];

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
        require(msg.sender == address(token), "Only payment token");
        require(to == address(this), "Tokens must be sent to this contract");

        (uint256 listingId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) = abi.decode(data, (uint256, uint256, uint8, bytes32, bytes32));
        _verifyPermitBuy(from, listingId, deadline, v, r, s);
        _executePurchaseCallback(from, listingId, amount);

        return true;
    }

    function getPriceInTokenUnits(uint256 _listingId) external view returns (uint256) {
        return listings[_listingId].priceInWei / (10 ** uint256(_decimals));
    }

    function _verifyPermitBuy(address buyer, uint256 listingId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) internal view {
        require(whitelistSigner != address(0), "Whitelist signer not set");
        require(block.timestamp <= deadline, "Permit expired");
        bytes32 structHash = keccak256(abi.encode(PERMIT_BUY_TYPEHASH, buyer, listingId, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = ECDSA.recover(digest, v, r, s);
        require(recovered == whitelistSigner, "Invalid permit signature");
    }

    function _executePurchaseDirect(address buyer, uint256 listingId, uint256 amountTokenUnits) internal {
        Listing storage l = listings[listingId];
        require(l.isActive, "Not listed");

        IERC721 nft = IERC721(l.nftContract);
        require(nft.ownerOf(l.tokenId) == l.seller, "NFT no longer for sale");

        uint256 amountInWei = amountTokenUnits * (10 ** uint256(_decimals));
        require(amountInWei >= l.priceInWei, "Insufficient amount");

        // 标准 ERC20：金额为最小单位（wei）；与自定义 MyToken 系列「整币入参」不兼容
        token.safeTransferFrom(buyer, l.seller, l.priceInWei);
        nft.transferFrom(l.seller, buyer, l.tokenId);

        l.isActive = false;
        delete activeListingByNft[keccak256(abi.encode(l.nftContract, l.tokenId))];

        emit Sold(listingId, buyer, l.seller, l.nftContract, l.tokenId, l.priceInWei);
    }

    function _executePurchaseCallback(address buyer, uint256 listingId, uint256 amountWei) internal {
        Listing storage l = listings[listingId];
        require(l.isActive, "Not listed");

        IERC721 nft = IERC721(l.nftContract);
        require(nft.ownerOf(l.tokenId) == l.seller, "NFT no longer for sale");
        require(amountWei >= l.priceInWei, "Insufficient amount");

        // transferWithCallback 仅适用于 MyTokenV2：transfer 入参为整币单位
        uint256 priceInTokenUnits = l.priceInWei / (10 ** uint256(_decimals));
        token.safeTransfer(l.seller, priceInTokenUnits);

        if (amountWei > l.priceInWei) {
            uint256 refundInWei = amountWei - l.priceInWei;
            uint256 refundInTokenUnits = refundInWei / (10 ** uint256(_decimals));
            if (refundInTokenUnits > 0) {
                token.safeTransfer(buyer, refundInTokenUnits);
            }
        }

        nft.transferFrom(l.seller, buyer, l.tokenId);

        l.isActive = false;
        delete activeListingByNft[keccak256(abi.encode(l.nftContract, l.tokenId))];

        emit Sold(listingId, buyer, l.seller, l.nftContract, l.tokenId, l.priceInWei);
    }
}
