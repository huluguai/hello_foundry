// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TokenVesting} from "../src/v2/vesting/TokenVesting.sol";

/// @dev 测试用 ERC20，任意地址可 mint。
contract VestingTestToken is ERC20 {
    constructor() ERC20("VestingTest", "VTST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TokenVestingTest is Test {
    uint64 internal constant CLIFF = uint64(12 * 30 days);
    uint64 internal constant LINEAR = uint64(24 * 30 days);
    uint256 internal constant SUPPLY = 1_000_000 * 10 ** 18;

    VestingTestToken internal token;
    TokenVesting internal vesting;
    address internal beneficiary;

    function setUp() public {
        beneficiary = makeAddr("beneficiary");
        token = new VestingTestToken();
        uint64 start = uint64(block.timestamp);
        vesting = new TokenVesting(beneficiary, address(token), start, CLIFF, LINEAR);
        token.mint(address(vesting), SUPPLY);
    }

    function test_Constructor_RevertZeroBeneficiary() public {
        vm.expectRevert(TokenVesting.ZeroAddress.selector);
        new TokenVesting(address(0), address(token), uint64(block.timestamp), CLIFF, LINEAR);
    }

    function test_Constructor_RevertZeroCliff() public {
        vm.expectRevert(TokenVesting.ZeroDuration.selector);
        new TokenVesting(beneficiary, address(token), uint64(block.timestamp), 0, LINEAR);
    }

    function test_Cliff_LastSecond_NoReleasable() public {
        uint256 cliffEnd_ = vesting.cliffEnd();
        vm.warp(cliffEnd_ - 1);
        assertEq(vesting.releasable(), 0);
    }

    function test_CliffEnd_ReleasableZero() public {
        vm.warp(vesting.cliffEnd());
        assertEq(vesting.releasable(), 0);
    }

    function test_Linear_OneTwentyFourth() public {
        uint256 cliffEnd_ = vesting.cliffEnd();
        vm.warp(cliffEnd_ + uint256(LINEAR) / 24);
        uint256 expected = SUPPLY / 24;
        assertEq(vesting.releasable(), expected);
    }

    function test_Linear_Half() public {
        uint256 cliffEnd_ = vesting.cliffEnd();
        vm.warp(cliffEnd_ + uint256(LINEAR) / 2);
        assertEq(vesting.releasable(), SUPPLY / 2);
    }

    function test_Full_TwoReleases() public {
        uint256 cliffEnd_ = vesting.cliffEnd();
        uint256 halfLinear = uint256(LINEAR) / 2;

        vm.warp(cliffEnd_ + halfLinear);
        uint256 first = vesting.releasable();
        assertEq(first, SUPPLY / 2);

        vesting.release();
        assertEq(token.balanceOf(beneficiary), first);
        assertEq(vesting.releasable(), 0);

        vm.warp(vesting.vestingEnd());
        uint256 second = vesting.releasable();
        assertEq(second, SUPPLY - first);

        vesting.release();
        assertEq(token.balanceOf(beneficiary), SUPPLY);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    function test_Release_EmitsERC20Released() public {
        vm.warp(vesting.cliffEnd() + uint256(LINEAR) / 4);
        uint256 amt = vesting.releasable();

        vm.expectEmit(true, true, true, true);
        emit TokenVesting.ERC20Released(address(token), amt);

        vesting.release();
    }
}
