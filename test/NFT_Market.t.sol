// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import "../src/NFT_Market.sol";
import "forge-std/console2.sol"; // 导入 console2
//模拟ERC20代币合约
contract MockERC20 is IExtendedERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping (address=>uint256)) private _allowances;
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1000000 * 10**18;
    constructor(){
        _balances[msg.sender] = totalSupply;
    }
    function balanceOf(address account) external override view returns(uint256){
        return _balances[account];
    }
    function transfer(address recipient, uint256 amount) external override returns(bool){
        _balances[msg.sender] -= amount;
        _balances[recipient] += amount;
        return true;
    }
    function transferFrom(address sender,address recipient,uint256 amount) external override returns(bool){
        require(_allowances[sender][recipient] >= amount, "ERC20: insfficient allowance");
         _balances[sender] -= amount;
        _balances[recipient] += amount;
        return true;
    }
    function approve(address spender, uint256 amount) external override returns(bool){
        _allowances[msg.sender][spender] = amount;
        return true;
    }
    function allowance(address owner, address spender) external view override returns(uint256){
        return _allowances[owner][spender];
    }
    function mint(address _to,uint256 _value) external {
        _balances[_to] += _value;
    }
    function transferWithCallback(address _to, uint256 _value) external override returns (bool){
        _balances[msg.sender] -= _value;
        _balances[_to] += _value;
        ITokenReceiver(_to).tokensReceived(msg.sender, _value, "");
        return true;
        
    }
    function transferWithCallbackAndData(address _to, uint256 _value, bytes calldata _data) external override returns (bool){
        _balances[msg.sender] -= _value;
        _balances[_to] += _value;
        ITokenReceiver(_to).tokensReceived(msg.sender, _value, _data);
        return true;
    }
}
// 模拟ERC721代币合约
contract MockeERC721 is IERC721 {
    mapping(uint256 => address) private _owners;
    mapping (address=>mapping (address=>bool)) _operatorApprovals;
    mapping (uint256=>address) _tokenApprovals;

    function mint(address to,uint256 tokenId) external{
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
    MockeERC721 public nftContract;

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
    function setUp() public {
        //部署代币合约
        paymentToken = new MockERC20();
        nftContract = new MockeERC721();
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

        
    }

}