// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LeverageDex} from "../../../src/v2/dex/LeverageDex.sol";

contract LeverageDexTest is Test {
    LeverageDex internal dex;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA101);
    address internal liquidator = address(0x110111);

    uint256 internal constant INIT_BASE = 1_000_000e18;
    uint256 internal constant INIT_QUOTE = 1_000_000e18;

    function setUp() public {
        dex = new LeverageDex(INIT_BASE, INIT_QUOTE);
    }

    function test_openPosition_long_updatesState() public {
        vm.prank(alice);
        dex.openPosition(1_000e18, 5, true);

        (uint256 margin, uint256 notional, uint256 size, bool isLong, uint256 entryPriceX18, bool isOpen) = dex.positions(alice);
        assertTrue(isOpen);
        assertTrue(isLong);
        assertEq(margin, 1_000e18);
        assertEq(notional, 5_000e18);
        assertGt(size, 0);
        assertGt(entryPriceX18, 1e18);
        assertLt(dex.vBaseReserve(), INIT_BASE);
        assertGt(dex.vQuoteReserve(), INIT_QUOTE);
    }

    function test_openPosition_short_updatesState() public {
        vm.prank(alice);
        dex.openPosition(2_000e18, 3, false);

        (uint256 margin, uint256 notional, uint256 size, bool isLong,, bool isOpen) = dex.positions(alice);
        assertTrue(isOpen);
        assertFalse(isLong);
        assertEq(margin, 2_000e18);
        assertEq(notional, 6_000e18);
        assertGt(size, 0);
        assertGt(dex.vBaseReserve(), INIT_BASE);
        assertLt(dex.vQuoteReserve(), INIT_QUOTE);
    }

    function test_RevertWhen_invalidLeverage_or_duplicatePosition() public {
        vm.startPrank(alice);
        vm.expectRevert(LeverageDex.InvalidLeverage.selector);
        dex.openPosition(1e18, 0, true);

        vm.expectRevert(LeverageDex.InvalidLeverage.selector);
        dex.openPosition(1e18, 11, true);

        dex.openPosition(1e18, 1, true);
        vm.expectRevert(LeverageDex.PositionExists.selector);
        dex.openPosition(1e18, 1, true);
        vm.stopPrank();
    }

    function test_closePosition_long_profit() public {
        vm.prank(alice);
        dex.openPosition(1_000e18, 5, true);

        // Bob 开多，推动价格上涨，帮助 Alice 多头盈利
        vm.prank(bob);
        dex.openPosition(300_000e18, 3, true);

        vm.prank(alice);
        uint256 settlement = dex.closePosition();
        assertGt(settlement, 1_000e18);

        (,,,,, bool isOpen) = dex.positions(alice);
        assertFalse(isOpen);
    }

    function test_closePosition_short_profit() public {
        vm.prank(alice);
        dex.openPosition(1_000e18, 5, false);

        // Carol 开空，推动价格下跌，帮助 Alice 空头盈利
        vm.prank(carol);
        dex.openPosition(250_000e18, 3, false);

        vm.prank(alice);
        uint256 settlement = dex.closePosition();
        assertGt(settlement, 1_000e18);
    }

    function test_RevertWhen_closeWithoutPosition() public {
        vm.prank(alice);
        vm.expectRevert(LeverageDex.NoOpenPosition.selector);
        dex.closePosition();
    }

    function test_liquidatePosition_success_and_rewardSplit() public {
        vm.prank(alice);
        dex.openPosition(500e18, 10, true);

        // 通过开空将价格明显压低，使 Alice 保证金率跌破维持保证金阈值
        vm.prank(bob);
        dex.openPosition(20_000e18, 8, false);

        uint256 ratio = dex.marginRatioBps(alice);
        assertLe(ratio, dex.MAINTENANCE_MARGIN_BPS());

        vm.prank(liquidator);
        (uint256 userSettlement, uint256 reward) = dex.liquidatePosition(alice);

        // 清算奖励按剩余权益 5% 分配
        uint256 totalRemaining = userSettlement + reward;
        assertEq(reward, (totalRemaining * dex.LIQUIDATION_REWARD_BPS()) / dex.BPS());
        (,,,,, bool isOpen) = dex.positions(alice);
        assertFalse(isOpen);
    }

    function test_RevertWhen_notLiquidatable() public {
        vm.prank(alice);
        dex.openPosition(1_000e18, 2, true);

        vm.prank(liquidator);
        vm.expectRevert(LeverageDex.NotLiquidatable.selector);
        dex.liquidatePosition(alice);
    }

    function test_extremeLoss_settlementIsZero() public {
        vm.prank(alice);
        dex.openPosition(200e18, 10, true);

        // 多次压价，构造极端亏损（协议亏损不考虑 -> 最低为 0）
        vm.startPrank(bob);
        dex.openPosition(95_000e18, 10, false);
        vm.stopPrank();

        vm.prank(alice);
        uint256 settlement = dex.closePosition();
        assertEq(settlement, 0);
    }
}
