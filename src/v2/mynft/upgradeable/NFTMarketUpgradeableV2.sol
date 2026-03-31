// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {NFTMarketUpgradeableV1} from "./NFTMarketUpgradeableV1.sol";

/**
 * @title NFTMarketUpgradeableV2
 * @notice 在 V1 基础上增加 EIP-712 签名上架（卖家 authorize 市场后可由任意提交者付 gas 上链）
 */
contract NFTMarketUpgradeableV2 is NFTMarketUpgradeableV1 {
    bytes32 private constant PERMIT_LIST_TYPEHASH =
        keccak256("PermitList(address seller,address nftContract,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)");

    mapping(address => uint256) public listingNonces;

    error InvalidListSignature();
    error ListSigExpired();
    error InvalidListingNonce();

    /**
     * @notice 卖家对 PermitList 签名后，任意地址可提交本交易完成上架
     * @param _price 整币价格（与 list 一致）
     */
    function listWithSig(
        address seller,
        address _nftContract,
        uint256 _tokenId,
        uint256 _price,
        uint256 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256) {
        if (_nftContract == address(0)) revert InvalidNFTContract();
        if (_price == 0) revert PriceMustBePositive();
        if (block.timestamp > deadline) revert ListSigExpired();
        _consumeListSignature(seller, _nftContract, _tokenId, _price, nonce, deadline, v, r, s);
        return _finalizeListing(seller, _nftContract, _tokenId, _price);
    }

    function _consumeListSignature(
        address seller,
        address _nftContract,
        uint256 _tokenId,
        uint256 _price,
        uint256 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        if (nonce != listingNonces[seller]) revert InvalidListingNonce();

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(PERMIT_LIST_TYPEHASH, seller, _nftContract, _tokenId, _price, nonce, deadline))
        );
        if (ECDSA.recover(digest, v, r, s) != seller) revert InvalidListSignature();

        if (IERC721(_nftContract).ownerOf(_tokenId) != seller) revert InvalidListSignature();
        unchecked {
            listingNonces[seller] = nonce + 1;
        }
    }

    function _finalizeListing(address seller, address _nftContract, uint256 _tokenId, uint256 _price)
        internal
        returns (uint256 listingId)
    {
        bytes32 key = keccak256(abi.encode(_nftContract, _tokenId));
        uint256 existingId = activeListingByNft[key];
        if (existingId != 0 && listings[existingId - 1].isActive) revert AlreadyListed();

        uint256 priceInWei = _price * tokenUnit;
        listingId = nextListingId;
        unchecked {
            nextListingId = listingId + 1;
        }

        listings[listingId] = Listing({seller: seller, nftContract: _nftContract, tokenId: _tokenId, priceInWei: priceInWei, isActive: true});
        activeListingByNft[key] = listingId + 1;

        emit Listed(listingId, seller, _nftContract, _tokenId, priceInWei);
    }
}
