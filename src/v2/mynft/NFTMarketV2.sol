// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {MyTokenV2} from "../mytoken/my_token_v2.sol";
import {ITokenRecipient} from "../mytoken/ITokenRecipient.sol";

/**
 * @title NFTMarket - 使用 MyTokenV2 购买 NFT 的市场合约
 * @dev 支持多 NFT 合约、list 上架、buyNFT 购买、transferWithCallback + tokensReceived 购买
 */
contract NFTMarket is ITokenRecipient {
    // ==================== 状态变量 ====================
    
    MyTokenV2 public token;
    
    struct Listing {
        address seller;
        address nftContract;   // NFT 合约地址，支持多集合
        uint256 tokenId;
        uint256 priceInWei;    // 价格（token 最小单位）
        bool isActive;         // 上架标识
    }
    
    mapping(uint256 => Listing) public listings;
    uint256 public nextListingId;
    
    /// @notice 防止同一 NFT 重复上架：(nftContract, tokenId) => listingId
    mapping(bytes32 => uint256) public activeListingByNft;
    
    // ==================== 事件 ====================
    
    event Listed(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 priceInWei);
    event Unlisted(uint256 indexed listingId, address indexed seller);
    event Sold(uint256 indexed listingId, address indexed buyer, address indexed seller, address nftContract, uint256 tokenId, uint256 priceInWei);
    
    // ==================== 构造函数 ====================
    
    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Invalid token address");
        token = MyTokenV2(_tokenAddress);
    }
    
    // ==================== 上架/下架 ====================
    
    /**
     * @notice NFT 持有者上架 NFT
     * @dev 调用前需 nft.approve(NFTMarket, tokenId) 或 setApprovalForAll
     * @param _nftContract NFT 合约地址
     * @param _tokenId NFT 的 tokenId
     * @param _price 价格（代币单位，如 100 表示 100 个 TOKEN）
     */
    function list(address _nftContract, uint256 _tokenId, uint256 _price) external returns (uint256) {
        require(_nftContract != address(0), "Invalid NFT contract");
        require(_price > 0, "Price must be > 0");
        
        IERC721 nft = IERC721(_nftContract);
        address owner = nft.ownerOf(_tokenId);
        require(
            owner == msg.sender ||
            nft.isApprovedForAll(owner, msg.sender) ||
            nft.getApproved(_tokenId) == msg.sender,
            "Not owner nor approved"
        );
        
        bytes32 key = keccak256(abi.encode(_nftContract, _tokenId));
        uint256 existingId = activeListingByNft[key];
        require(existingId == 0 || !listings[existingId - 1].isActive, "Already listed");
        
        uint256 priceInWei = _price * (10 ** uint256(token.decimals()));
        uint256 listingId = nextListingId++;
        
        listings[listingId] = Listing({
            seller: owner,
            nftContract: _nftContract,
            tokenId: _tokenId,
            priceInWei: priceInWei,
            isActive: true
        });
        activeListingByNft[key] = listingId + 1;
        
        emit Listed(listingId, owner, _nftContract, _tokenId, priceInWei);
        return listingId;
    }
    
    /**
     * @notice 下架 NFT
     */
    function unlist(uint256 _listingId) external {
        Listing storage l = listings[_listingId];
        require(l.isActive, "Not listed");
        require(l.seller == msg.sender, "Not lister");
        
        l.isActive = false;
        delete activeListingByNft[keccak256(abi.encode(l.nftContract, l.tokenId))];
        
        emit Unlisted(_listingId, msg.sender);
    }
    
    // ==================== 购买方式一：buyNFT（approve + transferFrom） ====================
    
    /**
     * @notice 使用 TOKEN 购买 NFT
     * @dev 调用前需 token.approve(NFTMarket, amount)
     * @param _listingId 上架 ID
     * @param _amount 支付的 TOKEN 数量（代币单位）
     */
    function buyNFT(uint256 _listingId, uint256 _amount) external {
        Listing storage l = listings[_listingId];
        require(l.isActive, "Not listed");
        
        IERC721 nft = IERC721(l.nftContract);
        require(nft.ownerOf(l.tokenId) == l.seller, "NFT no longer for sale");
        
        uint256 amountInWei = _amount * (10 ** uint256(token.decimals()));
        require(amountInWei >= l.priceInWei, "Insufficient amount");
        
        uint256 priceInTokenUnits = l.priceInWei / (10 ** uint256(token.decimals()));
        
        bool ok = token.transferFrom(msg.sender, l.seller, priceInTokenUnits);
        require(ok, "Token transfer failed");
        
        nft.transferFrom(l.seller, msg.sender, l.tokenId);
        
        l.isActive = false;
        delete activeListingByNft[keccak256(abi.encode(l.nftContract, l.tokenId))];
        
        emit Sold(_listingId, msg.sender, l.seller, l.nftContract, l.tokenId, l.priceInWei);
    }
    
    // ==================== 购买方式二：tokensReceived（transferWithCallback） ====================
    
    /**
     * @notice ERC20 扩展回调，在 transferWithCallback 时触发
     * @dev data 必须为 abi.encode(listingId)
     */
    function tokensReceived(
        address from,
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        require(msg.sender == address(token), "Only accept token from MyTokenV2");
        require(to == address(this), "Tokens must be sent to this contract");
        
        require(data.length >= 32, "Invalid data: need listingId");
        uint256 listingId = abi.decode(data, (uint256));
        
        Listing storage l = listings[listingId];
        require(l.isActive, "Not listed");
        
        IERC721 nft = IERC721(l.nftContract);
        require(nft.ownerOf(l.tokenId) == l.seller, "NFT no longer for sale");
        require(amount >= l.priceInWei, "Insufficient amount");
        
        uint256 decimals = token.decimals();
        uint256 priceInTokenUnits = l.priceInWei / (10 ** decimals);
        
        token.transfer(l.seller, priceInTokenUnits);
        
        if (amount > l.priceInWei) {
            uint256 refundInWei = amount - l.priceInWei;
            uint256 refundInTokenUnits = refundInWei / (10 ** decimals);
            if (refundInTokenUnits > 0) {
                token.transfer(from, refundInTokenUnits);
            }
        }
        
        nft.transferFrom(l.seller, from, l.tokenId);
        
        l.isActive = false;
        delete activeListingByNft[keccak256(abi.encode(l.nftContract, l.tokenId))];
        
        emit Sold(listingId, from, l.seller, l.nftContract, l.tokenId, l.priceInWei);
        
        return true;
    }
    
    // ==================== 辅助函数 ====================
    
    /// @notice 获取挂牌价（代币单位）
    function getPriceInTokenUnits(uint256 _listingId) external view returns (uint256) {
        return listings[_listingId].priceInWei / (10 ** uint256(token.decimals()));
    }
}