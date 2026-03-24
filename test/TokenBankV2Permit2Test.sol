// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {XZXToken} from "../src/v2/mytoken/xzx_token.sol";
import {TokenBankV2} from "../src/v2/mytoken/token_bank_v2.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/**
 * @title TokenBankV2Permit2Test
 * @dev 使用 MockPermit2 模拟链上 Permit2：owner 先 approve Mock，再由 relayer 代调 depositWithPermit2。
 */
contract TokenBankV2Permit2Test is Test {
    XZXToken internal token;
    MockPermit2 internal mockPermit2;
    TokenBankV2 internal bank;

    address internal owner;
    address internal relayer;

    function setUp() public {
        owner = makeAddr("owner");
        relayer = makeAddr("relayer");

        token = new XZXToken(1_000_000);
        mockPermit2 = new MockPermit2();
        bank = new TokenBankV2(address(token), address(mockPermit2));

        token.transfer(owner, 10_000 * 10 ** token.decimals());
    }

    function testDepositWithPermit2ByRelayer() public {
        uint256 amount = 1_000 * 10 ** token.decimals();
        uint160 amount160 = uint160(amount);

        vm.prank(owner);
        token.approve(address(mockPermit2), type(uint256).max);

        IAllowanceTransfer.PermitSingle memory permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: address(token),
                amount: amount160,
                expiration: uint48(block.timestamp + 1 days),
                nonce: 0
            }),
            spender: address(bank),
            sigDeadline: block.timestamp + 1 days
        });

        vm.prank(relayer);
        assertTrue(bank.depositWithPermit2(owner, permitSingle, hex""));

        assertEq(bank.deposits(owner), amount);
        assertEq(token.balanceOf(address(bank)), amount);
    }
}
