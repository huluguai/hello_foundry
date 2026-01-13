// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


import { Test } from "forge-std/Test.sol";
import { Bank } from "../src/Bank.sol";
import "forge-std/console2.sol"; // 导入 console2


contract BankTest is Test {
    Bank bank;
    //管理员
    address admin;

    //普通存款用户
    address user1;
    address user2;
    address user3;
    address user4;

    function setUp() public {
        //创建管理员用户
        admin = address(this);
        //创建普通存款用户 address
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");

        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
        vm.deal(user4, 10 ether);
        // 创建部署Bank合约
        bank = new Bank();
    }

    //测试存款  检查存款金额Bank合约余额是否正确
    function testDeposit() public {
        assertEq(bank.deposits(user1), 0);
        uint256 depositAmount = 1 ether;
        vm.prank(user1);
        bank.deposit{value:depositAmount}();
        assertEq(bank.deposits(user1), depositAmount);

        uint256 secondDepositAmount = 0.5 ether;
         vm.prank(user1);
        bank.deposit{value:secondDepositAmount}();
        assertEq(bank.deposits(user1), depositAmount + secondDepositAmount);
    }

    //测试 检查存款金额的前3名用户是否正确
    function testGetTopDepositArr() public {
        // 1个用户存款
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        (address[3] memory topAddr,uint256[3] memory amounts) = bank.getTopDepositors();
        console2.log("topAddr0:", topAddr[0]);
        console2.log("topAddr1:", topAddr[1]);
        console2.log("topAddr2:", topAddr[2]);
        assertEq(topAddr[0], user1);
        assertEq(amounts[0], 1 ether);
        assertEq(topAddr[1], address(0));
        assertEq(amounts[1], 0);
        assertEq(topAddr[2], address(0));
        assertEq(amounts[2], 0);
        //2个用户存款
        vm.prank(user2);
        bank.deposit{value: 2 ether}();
        (topAddr,amounts) = bank.getTopDepositors();
        console2.log("test2 topAddr0:", topAddr[0]);
        console2.log("test2 topAddr1:", topAddr[1]);
        console2.log("test2 topAddr2:", topAddr[2]);
        assertEq(topAddr[0], user2);
        assertEq(amounts[0], 2 ether);
        assertEq(topAddr[1], user1);
        assertEq(amounts[1], 1 ether);
        assertEq(topAddr[2], address(0));
        assertEq(amounts[2], 0);
        // 3个用户存款
        vm.prank(user3);
        bank.deposit{value: 1.5 ether}();
        (topAddr,amounts) = bank.getTopDepositors();
        console2.log("test3 topAddr0:", topAddr[0]);
        console2.log("test3 topAddr1:", topAddr[1]);
        console2.log("test3 topAddr2:", topAddr[2]);
        assertEq(topAddr[0], user2);
        assertEq(amounts[0], 2 ether);
        assertEq(topAddr[1], user3);
        assertEq(amounts[1], 1.5 ether);
        assertEq(topAddr[2], user1);
        assertEq(amounts[2], 1 ether);
        //4个用户存款 只记录前三名
        vm.prank(user4);
        bank.deposit{value: 0.5 ether}();
        (topAddr,amounts) = bank.getTopDepositors();
        console2.log("test4 topAddr0:", topAddr[0]);
        console2.log("test4 topAddr1:", topAddr[1]);
        console2.log("test4 topAddr2:", topAddr[2]);
        assertEq(topAddr[0], user2);
        assertEq(amounts[0], 2 ether);
        assertEq(topAddr[1], user3);
        assertEq(amounts[1], 1.5 ether);
        assertEq(topAddr[2], user1);
        assertEq(amounts[2], 1 ether);
        // 同一用户多次存款
        vm.prank(user1);
        bank.deposit{value: 3 ether}();
        (topAddr,amounts) = bank.getTopDepositors();
        console2.log("test5 topAddr0:", topAddr[0]);
        console2.log("test5 topAddr1:", topAddr[1]);
        console2.log("test5 topAddr2:", topAddr[2]);
        assertEq(topAddr[0], user1);
        assertEq(amounts[0], 4 ether);
        assertEq(topAddr[1], user2);
        assertEq(amounts[1], 2 ether);
        assertEq(topAddr[2], user3);
        assertEq(amounts[2], 1.5 ether);
    }

    // 测试只有管理员可以取款
    function testWithdraw() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        assertEq(address(bank).balance, 1 ether);
        vm.prank(user1);
        vm.expectRevert("only admin can withdraw");
        bank.withdraw();

        address bankAdmin = bank.admin();
        uint256 beforBalance = bankAdmin.balance;
        vm.prank(bankAdmin);
        bank.withdraw();
        uint256 afterBalance = bankAdmin.balance;

        assertEq(afterBalance - beforBalance, 1 ether);
        assertEq(address(bank).balance, 0);
    }

    receive() external payable {}
}