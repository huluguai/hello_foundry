// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {StakingPool} from "../../src/staking/StakingPool.sol";
import {KKToken} from "../../src/staking/KKToken.sol";
import {IWETH} from "../../src/staking/interfaces/IWETH.sol";
import {MockWETH} from "../../src/staking/mocks/MockWETH.sol";
import {MockERC4626Vault} from "../../src/staking/mocks/MockERC4626Vault.sol";

contract StakingPoolTest is Test {
    uint256 internal constant REWARD_PER_BLOCK = 10e18;

    MockWETH internal weth;
    MockERC4626Vault internal vault;
    KKToken internal kk;
    StakingPool internal pool;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        weth = new MockWETH();
        vault = new MockERC4626Vault(IERC20(address(weth)));
        kk = new KKToken(address(this));
        pool = new StakingPool(IWETH(address(weth)), IERC4626(address(vault)), kk, REWARD_PER_BLOCK);
        kk.setStakingPool(address(pool));

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function _wrap(address user, uint256 amt) internal {
        vm.startPrank(user);
        weth.deposit{value: amt}();
        weth.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice 单用户质押若干块后领取，奖励 = 块数 * rewardPerBlock。
    function test_singleUser_claimsBlockRewards() public {
        _wrap(alice, 5 ether);
        vm.prank(alice);
        pool.deposit(1 ether);

        vm.roll(block.number + 7);

        vm.prank(alice);
        pool.claim();

        assertEq(kk.balanceOf(alice), 7 * REWARD_PER_BLOCK);
    }

    /// @notice 无人质押时推进区块，之后再质押不应获得「空窗」期的 KK。
    function test_emptyPool_advancesLastRewardBlock_noRetroactiveRewards() public {
        uint256 deployedAt = block.number;
        _wrap(alice, 2 ether);

        vm.roll(deployedAt + 50);

        vm.prank(alice);
        pool.deposit(1 ether);

        vm.roll(block.number + 3);

        vm.prank(alice);
        pool.claim();

        assertEq(kk.balanceOf(alice), 3 * REWARD_PER_BLOCK);
    }

    /// @notice 两用户份额大致 1:1 时，新区间奖励大致均分。
    function test_twoUsers_splitRewardsByShareWeight() public {
        _wrap(alice, 5 ether);
        _wrap(bob, 5 ether);

        // 使用绝对块号，避免依赖 `block.number` 在多次 roll 之间的边界行为。
        uint256 b0 = 1_000_000;
        vm.roll(b0);

        vm.prank(alice);
        pool.deposit(1 ether);

        vm.roll(b0 + 10);

        vm.prank(bob);
        pool.deposit(1 ether);

        (uint256 sa,) = pool.userInfo(alice);
        (uint256 sb,) = pool.userInfo(bob);
        // 同一金库、连续 full-range 存款，份额应相等（允许 1 wei 舍入差）。
        assertApproxEqAbs(sa, sb, 2);

        vm.roll(b0 + 20);

        vm.prank(alice);
        pool.claim();
        vm.prank(bob);
        pool.claim();

        uint256 balA = kk.balanceOf(alice);
        uint256 balB = kk.balanceOf(bob);

        // 第一段 10 块仅 alice：100 KK；第二段 10 块两人各约一半：各约 50 KK。
        uint256 expectedA = 10 * REWARD_PER_BLOCK + (5 * REWARD_PER_BLOCK);
        uint256 expectedB = 5 * REWARD_PER_BLOCK;
        assertApproxEqAbs(balA, expectedA, 3);
        assertApproxEqAbs(balB, expectedB, 3);
    }

    /// @notice `depositETH` 与 WETH `deposit` 路径一致。
    function test_depositETH_wrapsAndStakes() public {
        vm.prank(alice);
        pool.depositETH{value: 2 ether}();

        vm.roll(block.number + 5);
        vm.prank(alice);
        pool.claim();

        assertEq(kk.balanceOf(alice), 5 * REWARD_PER_BLOCK);
    }

    /// @notice 向金库捐赠 WETH 模拟利息后，同份额赎回得到更多底层资产。
    function test_vaultYield_increasesRedeemableAssets() public {
        vm.prank(alice);
        pool.depositETH{value: 1 ether}();

        (uint256 shares,) = pool.userInfo(alice);
        uint256 assetsBeforeYield = vault.convertToAssets(shares);

        // 步骤：直接向金库注入资产，抬高份额净值（模拟借贷收益）。
        deal(address(weth), address(this), 0.5 ether);
        assertTrue(weth.transfer(address(vault), 0.5 ether));

        uint256 assetsAfterYield = vault.convertToAssets(shares);
        assertGt(assetsAfterYield, assetsBeforeYield);

        vm.prank(alice);
        pool.withdraw(shares);

        // 赎回的 WETH 应明显高于本金（含捐赠模拟的利息），允许舍入误差。
        assertGt(weth.balanceOf(alice), 1 ether);
    }

    /// @notice `pendingReward` 与事后 `claim` 一致（无其他用户干扰）。
    function test_pendingReward_matchesClaim() public {
        _wrap(alice, 2 ether);
        vm.prank(alice);
        pool.deposit(1 ether);

        vm.roll(block.number + 4);
        assertEq(pool.pendingReward(alice), 4 * REWARD_PER_BLOCK);

        vm.prank(alice);
        pool.claim();
        assertEq(kk.balanceOf(alice), 4 * REWARD_PER_BLOCK);
    }

    /// @notice 对照文档「逐块演算示例」按固定块高精确断言 acc/debt/pending 与实际发放。
    function test_blockByBlockAccounting_matchesDocScenario() public {
        _wrap(alice, 100 ether);
        _wrap(bob, 100 ether);

        uint256 b0 = 1_000_000;
        vm.roll(b0);

        // Step 1: block 100 -> A deposit 100 shares-equivalent assets.
        vm.prank(alice);
        pool.deposit(100 ether);
        (uint256 aShares0, uint256 aDebt0) = pool.userInfo(alice);
        assertEq(aShares0, 100 ether);
        assertEq(aDebt0, 0);
        assertEq(pool.totalShares(), 100 ether);

        // Step 2: block 103 -> B deposit 100; A pending should be 30 KK.
        vm.roll(b0 + 3);
        vm.prank(bob);
        pool.deposit(100 ether);
        (uint256 bShares0, uint256 bDebt0) = pool.userInfo(bob);
        assertEq(bShares0, 100 ether);
        assertEq(bDebt0, 30 ether);
        assertEq(pool.pendingReward(alice), 30 ether);

        // Step 3: block 106 -> A claim; should receive 45 KK.
        vm.roll(b0 + 6);
        assertEq(pool.pendingReward(alice), 45 ether);
        vm.prank(alice);
        pool.claim();
        assertEq(kk.balanceOf(alice), 45 ether);
        (, uint256 aDebt1) = pool.userInfo(alice);
        assertEq(aDebt1, 45 ether);

        // Step 4: block 108 -> A withdraw 50 shares; should harvest extra 10 KK first.
        vm.roll(b0 + 8);
        assertEq(pool.pendingReward(alice), 10 ether);
        vm.prank(alice);
        pool.withdraw(50 ether);
        assertEq(kk.balanceOf(alice), 55 ether);
        (uint256 aShares2, uint256 aDebt2) = pool.userInfo(alice);
        assertEq(aShares2, 50 ether);
        assertEq(aDebt2, 27.5 ether);
        assertEq(pool.totalShares(), 150 ether);

        // Step 5: block 110 -> B claim; pending should be 38.3333333333 KK (floor from acc precision).
        vm.roll(b0 + 10);
        uint256 expectedBPending = 38_333_333_333_300_000_000;
        assertEq(pool.pendingReward(bob), expectedBPending);
        vm.prank(bob);
        pool.claim();
        assertEq(kk.balanceOf(bob), expectedBPending);

        // At block 110, A still has unclaimed ~6.66666666665 KK.
        uint256 expectedAPending = 6_666_666_666_650_000_000;
        assertEq(pool.pendingReward(alice), expectedAPending);
    }
}
