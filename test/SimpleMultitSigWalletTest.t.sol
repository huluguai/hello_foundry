// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {SimpleMultitSigWallet} from "../src/SimpleMultitSigWallet.sol";

contract SimpleMultitSigWalletTest is Test {
    SimpleMultitSigWallet public wallet;
    
    address[] public owners;
    address public owner1;
    address public owner2;
    address public owner3;
    address public nonOwner;
    address public recipient;
    
    uint256 public constant REQUIRED = 2;
    
    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    event SubmitTransaction(uint256 indexed txId, address indexed destination, uint256 value, bytes data, address indexed proposer);
    event ConfirmTransaction(address indexed owner, uint256 indexed txId);
    event RevokeConfirmation(address indexed owner, uint256 indexed txId);
    event ExecuteTransaction(address indexed owner, uint256 indexed txId, bool success, bytes returnData);
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event RequirementChanged(uint256 required);
    
    function setUp() public {
        // 创建测试账户
        owner1 = address(0x1);
        owner2 = address(0x2);
        owner3 = address(0x3);
        nonOwner = address(0x4);
        recipient = address(0x5);
        
        // 初始化持有人列表
        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);
        
        // 部署多签钱包
        wallet = new SimpleMultitSigWallet(owners, REQUIRED);
        
        // 给测试账户分配ETH
        vm.deal(owner1, 10 ether);
        vm.deal(owner2, 10 ether);
        vm.deal(owner3, 10 ether);
        vm.deal(nonOwner, 10 ether);
        vm.deal(address(wallet), 5 ether);
    }
    
    // ============ 构造函数测试 ============
    
    function test_Constructor_Success() public {
        address[] memory testOwners = new address[](3);
        testOwners[0] = owner1;
        testOwners[1] = owner2;
        testOwners[2] = owner3;
        
        SimpleMultitSigWallet testWallet = new SimpleMultitSigWallet(testOwners, 2);
        
        assertEq(testWallet.required(), 2);
        assertEq(testWallet.getOwners().length, 3);
        assertTrue(testWallet.isOwner(owner1));
        assertTrue(testWallet.isOwner(owner2));
        assertTrue(testWallet.isOwner(owner3));
    }
    
    function test_Constructor_EmptyOwners() public {
        address[] memory emptyOwners = new address[](0);
        
        vm.expectRevert("Owners required");
        new SimpleMultitSigWallet(emptyOwners, 1);
    }
    
    function test_Constructor_InvalidRequired() public {
        address[] memory testOwners = new address[](2);
        testOwners[0] = owner1;
        testOwners[1] = owner2;
        
        vm.expectRevert("Invalid required number of confirmations");
        new SimpleMultitSigWallet(testOwners, 0);
        
        vm.expectRevert("Invalid required number of confirmations");
        new SimpleMultitSigWallet(testOwners, 3);
    }
    
    function test_Constructor_ZeroAddressOwner() public {
        address[] memory testOwners = new address[](2);
        testOwners[0] = address(0);
        testOwners[1] = owner1;
        
        vm.expectRevert("Invalid owner");
        new SimpleMultitSigWallet(testOwners, 1);
    }
    
    function test_Constructor_DuplicateOwners() public {
        address[] memory testOwners = new address[](2);
        testOwners[0] = owner1;
        testOwners[1] = owner1;
        
        vm.expectRevert("Owner not unique");
        new SimpleMultitSigWallet(testOwners, 1);
    }
    
    // ============ 接收ETH测试 ============
    
    function test_Receive_Ether() public {
        uint256 initialBalance = address(wallet).balance;
        uint256 depositAmount = 1 ether;
        
        vm.expectEmit(true, false, false, true);
        emit Deposit(owner1, depositAmount, initialBalance + depositAmount);
        
        vm.prank(owner1);
        (bool success,) = address(wallet).call{value: depositAmount}("");
        assertTrue(success);
        
        assertEq(address(wallet).balance, initialBalance + depositAmount);
    }
    
    // ============ 提交交易测试 ============
    
    function test_SubmitTransaction_Success() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        uint256 value = 1 ether;
        
        vm.expectEmit(true, true, false, true);
        emit SubmitTransaction(0, recipient, value, data, owner1);
        
        vm.expectEmit(true, true, false, true);
        emit ConfirmTransaction(owner1, 0);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, value, data);
        
        assertEq(txId, 0);
        assertEq(wallet.getTransactions(), 1);
        
        (address dest, uint256 val, bytes memory txData, bool executed, uint256 numConfirmations) = 
            wallet.getTransaction(0);
        assertEq(dest, recipient);
        assertEq(val, value);
        assertEq(txData, data);
        assertFalse(executed);
        assertEq(numConfirmations, 1); // 提交者自动确认
    }
    
    function test_SubmitTransaction_NotOwner() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(nonOwner);
        vm.expectRevert("Not an owner");
        wallet.submitTransaction(recipient, 1 ether, data);
    }
    
    function test_SubmitTransaction_InvalidDestination() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        vm.expectRevert("Invalid destination");
        wallet.submitTransaction(address(0), 1 ether, data);
    }
    
    function test_SubmitTransaction_InvalidValue() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        vm.expectRevert("Invalid value");
        wallet.submitTransaction(recipient, 0, data);
    }
    
    function test_SubmitTransaction_InvalidData() public {
        bytes memory emptyData = "";
        
        vm.prank(owner1);
        vm.expectRevert("Invalid data");
        wallet.submitTransaction(recipient, 1 ether, emptyData);
    }
    
    // ============ 确认交易测试 ============
    
    function test_ConfirmTransaction_Success() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, data);
        
        vm.expectEmit(true, true, false, true);
        emit ConfirmTransaction(owner2, txId);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        (,,, bool executed, uint256 numConfirmations) = wallet.getTransaction(txId);
        assertFalse(executed);
        assertEq(numConfirmations, 2);
        assertTrue(wallet.confirmations(txId, owner2));
    }
    
    function test_ConfirmTransaction_NotOwner() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, data);
        
        vm.prank(nonOwner);
        vm.expectRevert("Not an owner");
        wallet.confirmTransaction(txId);
    }
    
    function test_ConfirmTransaction_NotExists() public {
        vm.prank(owner1);
        vm.expectRevert("Transaction does not exist");
        wallet.confirmTransaction(999);
    }
    
    function test_ConfirmTransaction_AlreadyExecuted() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.prank(owner1);
        wallet.executeTransaction(txId);
        
        vm.prank(owner3);
        vm.expectRevert("Transaction already executed");
        wallet.confirmTransaction(txId);
    }
    
    function test_ConfirmTransaction_AlreadyConfirmed() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, data);
        
        vm.prank(owner1);
        vm.expectRevert("Transaction already confirmed");
        wallet.confirmTransaction(txId);
    }
    
    // ============ 撤销确认测试 ============
    
    function test_RevokeConfirmation_Success() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.expectEmit(true, true, false, true);
        emit RevokeConfirmation(owner1, txId);
        
        vm.prank(owner1);
        wallet.revokeConfirmation(txId);
        
        (,,, bool executed, uint256 numConfirmations) = wallet.getTransaction(txId);
        assertEq(numConfirmations, 1);
        assertFalse(wallet.confirmations(txId, owner1));
    }
    
    function test_RevokeConfirmation_NotConfirmed() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, data);
        
        vm.prank(owner2);
        vm.expectRevert("Transaction not confirmed");
        wallet.revokeConfirmation(txId);
    }
    
    // ============ 执行交易测试 ============
    
    function test_ExecuteTransaction_Success() public {
        uint256 amount = 1 ether;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, amount);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, amount, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        uint256 initialBalance = recipient.balance;
        uint256 walletBalance = address(wallet).balance;
        
        vm.expectEmit(true, true, false, true);
        emit ExecuteTransaction(owner1, txId, true, "");
        
        vm.prank(owner1);
        wallet.executeTransaction(txId);
        
        assertEq(recipient.balance, initialBalance + amount);
        assertEq(address(wallet).balance, walletBalance - amount);
        
        (,,, bool executed,) = wallet.getTransaction(txId);
        assertTrue(executed);
    }
    
    function test_ExecuteTransaction_NotEnoughConfirmations() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, data);
        
        vm.prank(owner1);
        vm.expectRevert("Not enough confirmations");
        wallet.executeTransaction(txId);
    }
    
    function test_ExecuteTransaction_NotExists() public {
        vm.prank(owner1);
        vm.expectRevert("Transaction does not exist");
        wallet.executeTransaction(999);
    }
    
    function test_ExecuteTransaction_AlreadyExecuted() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.prank(owner1);
        wallet.executeTransaction(txId);
        
        vm.prank(owner1);
        vm.expectRevert("Transaction already executed");
        wallet.executeTransaction(txId);
    }
    
    function test_ExecuteTransaction_AnyoneCanExecute() public {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        // 非持有人也可以执行
        vm.prank(nonOwner);
        wallet.executeTransaction(txId);
        
        (,,, bool executed,) = wallet.getTransaction(txId);
        assertTrue(executed);
    }
    
    // ============ 修改所需确认数测试 ============
    
    function test_ChangeRequirement_Success() public {
        vm.expectEmit(true, false, false, true);
        emit RequirementChanged(3);
        
        vm.prank(owner1);
        wallet.changeRequirement(3);
        
        assertEq(wallet.required(), 3);
    }
    
    function test_ChangeRequirement_NotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Not an owner");
        wallet.changeRequirement(3);
    }
    
    function test_ChangeRequirement_InvalidRequired() public {
        vm.prank(owner1);
        vm.expectRevert("Invalid required number of confirmations");
        wallet.changeRequirement(0);
        
        vm.prank(owner1);
        vm.expectRevert("Invalid required number of confirmations");
        wallet.changeRequirement(4);
    }
    
    // ============ 添加/删除持有人测试 ============
    
    function test_AddOwner_OnlyContract() public {
        address newOwner = address(0x6);
        
        // 直接调用应该失败
        vm.prank(owner1);
        vm.expectRevert("Only contract itself can add owners");
        wallet.addOwner(newOwner);
        
        // 通过交易提案添加
        bytes memory data = abi.encodeWithSignature("addOwner(address)", newOwner);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(wallet), 0, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.expectEmit(true, false, false, true);
        emit OwnerAdded(newOwner);
        
        vm.prank(owner1);
        wallet.executeTransaction(txId);
        
        assertTrue(wallet.isOwner(newOwner));
        assertEq(wallet.getOwners().length, 4);
    }
    
    function test_RemoveOwner_OnlyContract() public {
        // 直接调用应该失败
        vm.prank(owner1);
        vm.expectRevert("Only contract itself can remove owners");
        wallet.removeOwner(owner3);
        
        // 通过交易提案删除
        bytes memory data = abi.encodeWithSignature("removeOwner(address)", owner3);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(wallet), 0, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.expectEmit(true, false, false, true);
        emit OwnerRemoved(owner3);
        
        vm.prank(owner1);
        wallet.executeTransaction(txId);
        
        assertFalse(wallet.isOwner(owner3));
        assertEq(wallet.getOwners().length, 2);
    }
    
    function test_RemoveOwner_AdjustRequired() public {
        // 设置required为3
        vm.prank(owner1);
        wallet.changeRequirement(3);
        
        // 删除一个持有人，required应该自动调整为2
        bytes memory data = abi.encodeWithSignature("removeOwner(address)", owner3);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(wallet), 0, data);
        
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        vm.expectEmit(true, false, false, true);
        emit RequirementChanged(2);
        
        vm.prank(owner1);
        wallet.executeTransaction(txId);
        
        assertEq(wallet.required(), 2);
    }
    
    function test_RemoveOwner_LastOwner() public {
        // 先删除两个持有人，只剩一个
        bytes memory data1 = abi.encodeWithSignature("removeOwner(address)", owner3);
        vm.prank(owner1);
        uint256 txId1 = wallet.submitTransaction(address(wallet), 0, data1);
        vm.prank(owner2);
        wallet.confirmTransaction(txId1);
        vm.prank(owner1);
        wallet.executeTransaction(txId1);
        
        bytes memory data2 = abi.encodeWithSignature("removeOwner(address)", owner2);
        vm.prank(owner1);
        uint256 txId2 = wallet.submitTransaction(address(wallet), 0, data2);
        vm.prank(owner1);
        wallet.executeTransaction(txId2);
        
        // 尝试删除最后一个持有人应该失败
        bytes memory data3 = abi.encodeWithSignature("removeOwner(address)", owner1);
        vm.prank(owner1);
        uint256 txId3 = wallet.submitTransaction(address(wallet), 0, data3);
        vm.prank(owner1);
        
        vm.expectRevert("At least one owner is required");
        wallet.executeTransaction(txId3);
    }
    
    // ============ 视图函数测试 ============
    
    function test_GetOwners() public {
        address[] memory retrievedOwners = wallet.getOwners();
        assertEq(retrievedOwners.length, 3);
        assertEq(retrievedOwners[0], owner1);
        assertEq(retrievedOwners[1], owner2);
        assertEq(retrievedOwners[2], owner3);
    }
    
    function test_GetBalance() public {
        assertEq(wallet.getBalance(), 5 ether);
        
        vm.deal(address(wallet), 10 ether);
        assertEq(wallet.getBalance(), 10 ether);
    }
    
    function test_IsOwner() public {
        assertTrue(wallet.isOwner(owner1));
        assertTrue(wallet.isOwner(owner2));
        assertTrue(wallet.isOwner(owner3));
        assertFalse(wallet.isOwner(nonOwner));
    }
    
    // ============ 完整流程测试 ============
    
    function test_CompleteFlow() public {
        // 1. 接收ETH
        vm.deal(owner1, 10 ether);
        vm.prank(owner1);
        (bool success,) = address(wallet).call{value: 2 ether}("");
        assertTrue(success);
        assertEq(address(wallet).balance, 7 ether);
        
        // 2. 提交交易
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, data);
        
        // 3. 确认交易
        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        
        // 4. 执行交易
        uint256 recipientBalance = recipient.balance;
        vm.prank(owner3);
        wallet.executeTransaction(txId);
        
        assertEq(recipient.balance, recipientBalance + 1 ether);
        assertEq(address(wallet).balance, 6 ether);
        
        // 5. 验证交易已执行
        (,,, bool executed, uint256 numConfirmations) = wallet.getTransaction(txId);
        assertTrue(executed);
        assertEq(numConfirmations, 2);
    }
    
    // ============ Fuzz测试 ============
    
    function testFuzz_SubmitTransaction(uint256 value) public {
        vm.assume(value > 0 && value <= address(wallet).balance);
        
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, value);
        
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, value, data);
        
        (address dest, uint256 val,, bool executed, uint256 numConfirmations) = 
            wallet.getTransaction(txId);
        assertEq(dest, recipient);
        assertEq(val, value);
        assertFalse(executed);
        assertEq(numConfirmations, 1);
    }
}