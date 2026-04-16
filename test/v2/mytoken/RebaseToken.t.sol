// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "../../../src/v2/mytoken/RebaseToken.sol";

contract RebaseTokenTest is Test {
    uint256 internal constant SCALE = 1e18;
    uint256 internal constant INITIAL_SUPPLY = 100_000_000 * 1e18;
    uint256 internal constant ANNUAL_RATIO = 99e16; // 0.99 * 1e18

    RebaseToken internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new RebaseToken();
        token.transfer(alice, 40_000_000 * 1e18);
        token.transfer(bob, 10_000_000 * 1e18);
    }

    function test_InitialSupplyAndBalances() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(address(this)), 50_000_000 * 1e18);
        assertEq(token.balanceOf(alice), 40_000_000 * 1e18);
        assertEq(token.balanceOf(bob), 10_000_000 * 1e18);
    }

    function test_RebaseAfterOneYear_ReducesByOnePercent() public {
        vm.warp(block.timestamp + 365 days);
        token.rebase();

        uint256 expectedSupply = _applyRatio(INITIAL_SUPPLY, 1);
        assertEq(token.totalSupply(), expectedSupply);
        assertEq(token.balanceOf(alice), _applyRatio(40_000_000 * 1e18, 1));
        assertEq(token.balanceOf(bob), _applyRatio(10_000_000 * 1e18, 1));
        assertEq(token.balanceOf(address(this)), _applyRatio(50_000_000 * 1e18, 1));
    }

    function test_RebaseAfterThreeYears_CompoundsCorrectly() public {
        vm.warp(block.timestamp + 3 * 365 days);
        token.rebase();

        assertEq(token.totalSupply(), _applyRatio(INITIAL_SUPPLY, 3));
        assertEq(token.balanceOf(alice), _applyRatio(40_000_000 * 1e18, 3));
        assertEq(token.balanceOf(bob), _applyRatio(10_000_000 * 1e18, 3));
    }

    function test_RebaseBeforeOneYear_NoChange() public {
        uint256 supplyBefore = token.totalSupply();
        uint256 aliceBefore = token.balanceOf(alice);

        vm.warp(block.timestamp + 364 days);
        token.rebase();

        assertEq(token.totalSupply(), supplyBefore);
        assertEq(token.balanceOf(alice), aliceBefore);
    }

    function test_TransferAfterRebase_ShowsCorrectBalances() public {
        vm.warp(block.timestamp + 2 * 365 days);
        token.rebase();

        uint256 transferAmount = 1_000 * 1e18;
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);

        vm.prank(alice);
        token.transfer(bob, transferAmount);

        uint256 aliceAfter = token.balanceOf(alice);
        uint256 bobAfter = token.balanceOf(bob);
        uint256 aliceDecrease = aliceBefore - aliceAfter;
        uint256 bobIncrease = bobAfter - bobBefore;

        // 可见余额受定点取整影响，单次转账允许 1 wei 偏差。
        assertTrue(aliceDecrease >= transferAmount && aliceDecrease <= transferAmount + 1);
        assertTrue(bobIncrease <= transferAmount && bobIncrease + 1 >= transferAmount);
        uint256 visibleTracked = token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob);
        uint256 visibleSupply = token.totalSupply();
        assertTrue(visibleSupply >= visibleTracked);
        assertTrue(visibleSupply - visibleTracked <= 1);
    }

    function _applyRatio(uint256 amount, uint256 years_) internal pure returns (uint256 result) {
        result = amount;
        for (uint256 i = 0; i < years_; i++) {
            result = (result * ANNUAL_RATIO) / SCALE;
        }
    }
}
