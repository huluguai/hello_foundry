// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import "../src/NFT_Market.sol";
import "forge-std/console2.sol"; // 导入 console2
// 模拟ERC20代币合约
contract MockERC20 is IExtendedERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1000000 * 10**18;
    
    constructor() {
        _balances[msg.sender] = totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[recipient] += amount;
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(_allowances[sender][msg.sender] >= amount, "ERC20: insufficient allowance");
        _allowances[sender][msg.sender] -= amount;
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }
    
    function transferWithCallback(address _to, uint256 _value) external override returns (bool) {
        _balances[msg.sender] -= _value;
        _balances[_to] += _value;
        ITokenReceiver(_to).tokensReceived(msg.sender, _value, "");
        return true;

    }
    
    function transferWithCallbackAndData(address _to, uint256 _value, bytes calldata _data) external override returns (bool) {
        _balances[msg.sender] -= _value;
        _balances[_to] += _value;
        ITokenReceiver(_to).tokensReceived(msg.sender, _value, _data);
        return true;
    }
}

// 模拟ERC721代币合约
contract MockERC721 is IERC721 {
    mapping(uint256 => address) private _owners;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => address) private _tokenApprovals;
    
    function mint(address to, uint256 tokenId) external {
        _owners[tokenId] = to;
    }
    
    function ownerOf(uint256 tokenId) external view override returns (address) {
        require(_owners[tokenId] != address(0), "ERC721: owner query for nonexistent token");
        return _owners[tokenId];
    }
    
    function transferFrom(address /*from*/, address to, uint256 tokenId) external override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");
        _owners[tokenId] = to;
    }
    
    function safeTransferFrom(address /*from*/, address to, uint256 tokenId) external override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");
        _owners[tokenId] = to;
    }
    
    function approve(address to, uint256 tokenId) external {
        address owner = _owners[tokenId];
        require(msg.sender == owner || _operatorApprovals[owner][msg.sender], "ERC721: approve caller is not owner nor approved for all");
        _tokenApprovals[tokenId] = to;
    }
    
    function getApproved(uint256 tokenId) external view override returns (address) {
        return _tokenApprovals[tokenId];
    }
    
    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
    }
    
    function isApprovedForAll(address owner, address operator) external view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }
    
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _owners[tokenId];
        return (spender == owner || 
                _operatorApprovals[owner][spender] || 
                _tokenApprovals[tokenId] == spender);
    }

}

contract NFTMarketTest is Test {
    NFTMarket public market;
    MockERC20 public paymentToken;
    MockERC721 public nftContract;

    address public seller = address(1);
    address public buyer = address(2);
    address public operator = address(3);

    uint256 public tokenId = 1;
    uint256 public price = 100 * 10 ** 18;
    event NFTListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price
    );
    event NFTSold(
        uint256 indexed listingId, 
        address indexed buyer,
        address indexed seller, 
        address nftContract, 
        uint256 tokenId, 
        uint256 price
    );

    function setUp() public {
        //部署代币合约
        paymentToken = new MockERC20();
        nftContract = new MockERC721();
        //部署Market合约
        market = new NFTMarket(address(paymentToken));
        //为测试账号铸造NFT和Token
        paymentToken.mint(buyer, 1000 * 10 ** 18);
        nftContract.mint(seller, tokenId);
        //设置测试账号标签
        vm.label(seller,"seller");
        vm.label(buyer,"buyer");
        vm.label(operator,"operator");
        vm.label(address(market),"NFTMarket");
    }


    //测试NFT上架成功
    function testListNFTSuccess() public{
        vm.startPrank(seller);
        //预期上架事件
        vm.expectEmit(true, true, true, true);
        // emit NFTMarket.NFTListed(0, seller, address(nftContract), tokenId, price);
        emit NFTListed(0, seller, address(nftContract), tokenId, price);
        //上架NFT
        uint256 listingId = market.list(address(nftContract), tokenId, price);
        (address listedSeller,address listedNftContract,uint256 listedTokenId,uint256 listedPrice,bool isActive) = market.listings(listingId);
        assertEq(listedSeller, seller,"Seller address mismatch");
        assertEq(listedNftContract, address(nftContract),"NFT Contract addres mismatch");
        assertEq(listedTokenId, tokenId,"Token ID mismatch");
        assertEq(listedPrice, price,"Price mismatch");
        assertTrue(isActive,"Listing should be active");
        //验证listingId
        assertEq(listingId, 0,"Fist listing ID should be 0");
        assertEq(market.nextListingId(), 1,"Next listing ID should be incremented");
        vm.stopPrank();
    }
    //测试非NF所有者上架NFT失败
    function testListNFTFailurNotOwner() public{
        vm.startPrank(buyer);
        vm.expectRevert("NFTMarket: caller is not owner nor approved");
        market.list(address(nftContract), tokenId, price);
        vm.stopPrank();
    }
    //测试NFT地址为零上架NFT失败
    function testListNFTFailurZeroAddress() public{
        vm.startPrank(seller);
        vm.expectRevert("NFTMarket: NFT contract address cannot be zero");
        market.list(address(0), tokenId, price);
        vm.stopPrank();
    }
     //测试NFT价格为零上架NFT失败
    function testNFTFailurZeroPrice() public{
        vm.startPrank(seller);
        vm.expectRevert("NFTMarket: price must be greater than zero");
        market.list(address(nftContract), tokenId, 0);
        vm.stopPrank();
    }
    //测试授权操作员上架NFT成功的情况
    function testListNFTByApprovalOperatorSuccess() public{
        //卖家授权
        vm.startPrank(seller);
        nftContract.setApprovalForAll(operator, true);
        vm.stopPrank();
        //切换到操作员
        vm.startPrank(operator);
        //预期事件
        vm.expectEmit(true, true, true, true);
        emit NFTListed(0, seller, address(nftContract), tokenId, price);
        uint256 listingId = market.list(address(nftContract), tokenId, price);
        (address listedSeller, , , ,) = market.listings(listingId);
        assertEq(listedSeller, seller,"Seller should be the NFT owner, not the operator");
        vm.stopPrank();
    }
    //测试单个授权上架NFT成功
    function testListNFTByApprovalForToken() public {
        vm.startPrank(seller);
        nftContract.approve(operator, tokenId);
        vm.stopPrank();
        vm.startPrank(operator);
        vm.expectEmit(true,true,true,true);
        emit NFTListed(0, seller, address(nftContract), tokenId, price);
        uint256 listingId = market.list(address(nftContract), tokenId, price);
        (address listedSeller, , , ,) = market.listings(listingId);
        assertEq(listedSeller, seller,"Seller should be the NFT owner, not the operator");
        vm.stopPrank();
    }
    //测试购买NFT成功
    function testByNFTSuccess() public {
        //上架 NFT 授权Market操作 NFT
        vm.startPrank(seller);
        uint256 listingId = market.list(address(nftContract), tokenId, price);
        console2.log("listingId:", listingId);
        nftContract.approve(address(market), tokenId);
        vm.stopPrank();
        //切换买家 授权 Market合约转移token
        vm.startPrank(buyer);
        paymentToken.approve(address(market), price);
        //预期发生购买事件
        vm.expectEmit(true, true, true, true);
        emit NFTSold(listingId, buyer, seller, address(nftContract), tokenId, price);
        market.buyNFT(listingId);
        //验证NFT已转移
        console2.log("nftContract.ownerOf(tokenId)",nftContract.ownerOf(tokenId));
        console2.log("buyer",buyer);
        assertEq(nftContract.ownerOf(tokenId),buyer,"NFT ownership should be transferred to buyer");
        //验证代币已转移
        console2.log("paymentToken.balanceOf(seller)",paymentToken.balanceOf(seller));
        console2.log("seller",seller);
        assertEq(paymentToken.balanceOf(seller),price,"Payment should be transferred to seller");
        ( , , , ,bool isActive) = market.listings(listingId);
        assertFalse(isActive,"Listing should be inactive after purchase");
        vm.stopPrank();
    }
    //测试自己购买自己的NFT
    function testBySelfNFTSuccess() public{
        paymentToken.mint(seller, 1000 * 10 ** 18);
        vm.startPrank(seller);
        nftContract.approve(address(market),tokenId);
        paymentToken.approve(address(market),price);
        uint256 listingId = market.list(address(nftContract), tokenId, price);
        vm.expectEmit(true, true, true, true);
        emit NFTSold(listingId, seller, seller, address(nftContract), tokenId, price);
        market.buyNFT(listingId);
        assertEq(nftContract.ownerOf(tokenId),seller,"NFT ownership should be remain with seller");
         ( , , , ,bool isActive) = market.listings(listingId);
        assertFalse(isActive,"Listing should be inactive after purchase");
        vm.stopPrank();
    }
    //测试NFT被重复购买的情况
    function testByNFTTwice() public {
        vm.startPrank(seller);
        uint256 listingId = market.list(address(nftContract), tokenId, price);
        nftContract.approve(address(market), tokenId);
        vm.stopPrank();
        vm.startPrank(buyer);
        paymentToken.approve(address(market), price);
        market.buyNFT(listingId);
        vm.expectRevert("NFTMarket: listing is not active");
        market.buyNFT(listingId);
        vm.stopPrank();
    }
    //测试支付token过少
    function testBuyNFTinSufficientBalance() public {
        vm.startPrank(seller);
        uint256 listingId = market.list(address(nftContract), tokenId, price);
        vm.stopPrank();
        address poorBuyer = address(4);
        vm.label(poorBuyer, "poorBuyer");
        paymentToken.mint(poorBuyer, price / 2);
        vm.startPrank(poorBuyer);
        paymentToken.approve(address(market), price);
        vm.expectRevert("NFTMarket: insufficient token balance");
        market.buyNFT(listingId);
        vm.stopPrank();
    }
    //测试回调方式支付过多token的情况
    function testBuyNFTWithCallBackIncorrectAmount() public {
        vm.startPrank(seller);
        uint256 listingId = market.list(address(nftContract), tokenId, price);
        vm.stopPrank();
        //设置一个过多的价格
        uint256 incorrectPrice = price * 2;
        vm.startPrank(buyer);
        paymentToken.approve(address(market), incorrectPrice);
        bytes memory data = abi.encode(listingId);
        vm.expectRevert("NFTMarket: incorrect payment amount");
        paymentToken.transferWithCallbackAndData(address(market), incorrectPrice, data);
        vm.stopPrank();
    }
    //测回调方式购买成功
    function testBuyNFTWithCallBackSuccess() public {
        vm.startPrank(seller);
        uint256 listingId = market.list(address(nftContract), tokenId, price);
        nftContract.approve(address(market), tokenId);
        vm.stopPrank();
        vm.startPrank(buyer);
        paymentToken.approve(address(market), price);
        bytes memory data = abi.encode(listingId);
        vm.expectEmit(true, true, true, true);
        emit NFTSold(listingId, buyer, seller, address(nftContract), tokenId, price);
        paymentToken.transferWithCallbackAndData(address(market), price, data);
        assertEq(nftContract.ownerOf(tokenId),buyer,"NFT ownership should be transferred to buyer");
        assertEq(paymentToken.balanceOf(seller), price,"Payment should be transferred to seller");
       ( , , , ,bool isActive) = market.listings(listingId);
        assertFalse(isActive,"Listing should be inactive after purchase");
        vm.stopPrank();

    }
    //模糊测试 随机价格上架 随机地址购买
    function testFuzz_ListAndBuyNFT(uint256 fuzzPrice,address fuzzBuyer) public {
        //设置价格区间
        uint256 listingPrice = bound(fuzzPrice, 10**16, 10000 * 10 ** 18);
        //设置有效地址
        vm.assume(fuzzBuyer != address(0));
        vm.assume(fuzzBuyer != address(this));
        vm.assume(fuzzBuyer != address(seller));
        vm.assume(fuzzBuyer != address(market));
        paymentToken.mint(fuzzBuyer,listingPrice * 2);
        vm.startPrank(seller);
        uint256 listingId = market.list(address(nftContract), tokenId, listingPrice);
        nftContract.approve(address(market), tokenId);
        vm.stopPrank();
        vm.startPrank(fuzzBuyer);
        paymentToken.approve(address(market), listingPrice);
        vm.expectEmit(true, true, true, true);
        emit NFTSold(listingId, fuzzBuyer, seller, address(nftContract), tokenId, listingPrice);
        market.buyNFT(listingId);
        assertEq(nftContract.ownerOf(tokenId),fuzzBuyer,"NFT ownership should be transferred to buyer");
        assertEq(paymentToken.balanceOf(seller),listingPrice,"Payment should be transferred to seller");
        ( , , , ,bool isActive) = market.listings(listingId);
        assertFalse(isActive,"Listing should be inactive after purchase");
        vm.stopPrank();
    }
    //不可变测试 无论如何买卖 NFTMarket合约中不能有Token持仓
    function testInvariant_NoTokenBalace() public {
        //初始场景
        vm.startPrank(seller);
        uint256 listingId = market.list(address(nftContract), tokenId, price);
        nftContract.approve(address(market), tokenId);
        vm.stopPrank();
        vm.startPrank(buyer);
        paymentToken.approve(address(market), price);
        market.buyNFT(listingId);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(market)), 0, "Market contract should not hold any tokens");
        //再次上架
        vm.startPrank(buyer);
        uint256 newListingId = market.list(address(nftContract), tokenId, price * 2);
        nftContract.approve(address(market), tokenId);
        vm.stopPrank();
        paymentToken.mint(seller, price * 2);
        vm.startPrank(seller);
        paymentToken.approve(address(market), price * 2);
        market.buyNFT(newListingId);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(market)), 0, "Market contract should not hold any tokens");
        vm.startPrank(seller);
        uint256 callBackListingId = market.list(address(nftContract), tokenId, price);
        nftContract.approve(address(market), tokenId);
        vm.stopPrank();
        vm.startPrank(buyer);
        paymentToken.approve(address(market), price);
        bytes memory data = abi.encode(callBackListingId);
        paymentToken.transferWithCallbackAndData(address(market), price, data);
        vm.stopPrank();
        assertEq(paymentToken.balanceOf(address(market)), 0, "Market contract should not hold any tokens");

    }



}