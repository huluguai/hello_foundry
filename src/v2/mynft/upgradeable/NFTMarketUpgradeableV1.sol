// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ITokenRecipient} from "../../mytoken/ITokenRecipient.sol";

/**
 * @title NFTMarketUpgradeableV1 - 与 NFTMarket（NFTMarketV2.sol）逻辑对齐的可升级版本
 */
contract NFTMarketUpgradeableV1 is Initializable, OwnableUpgradeable, EIP712Upgradeable, UUPSUpgradeable, ITokenRecipient {
    using SafeERC20 for IERC20;

    bytes32 private constant PERMIT_BUY_TYPEHASH =
        keccak256("PermitBuy(address buyer,uint256 listingId,uint256 deadline)");

    IERC20 public token;
    uint256 public tokenUnit;

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

    uint256[50] private __gap;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address paymentToken, address initialWhitelistSigner, address initialOwner) public initializer {
        if (paymentToken == address(0)) revert InvalidTokenAddress();
        __Ownable_init(initialOwner);
        __EIP712_init("NFTMarket", "1");
        token = IERC20(paymentToken);
        uint256 unit;
        unchecked {
            unit = 10 ** uint256(IERC20Metadata(paymentToken).decimals());
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

    function buyNFT(uint256, uint256) external pure {
        revert BuyNFTDisabled();
    }

    function permitBuy(uint256 listingId, uint256 _amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        _verifyPermitBuy(msg.sender, listingId, deadline, v, r, s);
        _executePurchaseDirect(msg.sender, listingId, _amount);
    }

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

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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
