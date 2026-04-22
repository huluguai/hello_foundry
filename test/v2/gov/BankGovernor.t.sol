// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GovToken} from "../../../src/v2/gov/GovToken.sol";
import {BankGovernor} from "../../../src/v2/gov/BankGovernor.sol";
import {Bank} from "../../../src/Bank.sol";

contract BankGovernorTest is Test {
    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;

    GovToken internal token;
    BankGovernor internal governor;
    Bank internal bank;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        token = new GovToken(address(this), INITIAL_SUPPLY);
        governor = new BankGovernor(token);
        bank = governor.bank();

        token.transfer(alice, 600_000 ether);
        token.transfer(bob, 300_000 ether);
        token.transfer(carol, 100_000 ether);

        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(carol);
        token.delegate(carol);
    }

    function test_ProposalVoteExecuteWithdraw() public {
        _fundBank(10 ether);

        (uint256 proposalId, bytes32 descriptionHash,,,) = _createWithdrawProposal("withdraw treasury to governor");

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);
        vm.prank(carol);
        governor.castVote(proposalId, 0);

        vm.roll(block.number + governor.votingPeriod() + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(bank);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(Bank.withdraw, ());

        uint256 govBalanceBefore = address(governor).balance;
        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(address(bank).balance, 0);
        assertEq(address(governor).balance, govBalanceBefore + 10 ether);
    }

    function test_Revert_When_NoVotesOrNotPassed() public {
        _fundBank(2 ether);

        (uint256 proposalId, bytes32 descriptionHash,,,) = _createWithdrawProposal("proposal should fail");

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 0);
        vm.prank(bob);
        governor.castVote(proposalId, 0);

        vm.roll(block.number + governor.votingPeriod() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));

        address[] memory targets = new address[](1);
        targets[0] = address(bank);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(Bank.withdraw, ());

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function test_Revert_When_ExecuteBeforeDeadline() public {
        _fundBank(1 ether);

        (uint256 proposalId, bytes32 descriptionHash,,,) = _createWithdrawProposal("execute too early");

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        address[] memory targets = new address[](1);
        targets[0] = address(bank);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(Bank.withdraw, ());

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));
    }

    function _createWithdrawProposal(string memory description)
        internal
        returns (uint256 proposalId, bytes32 descriptionHash, address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        targets[0] = address(bank);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(Bank.withdraw, ());
        descriptionHash = keccak256(bytes(description));

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, description);
    }

    function _fundBank(uint256 amount) internal {
        vm.deal(address(this), amount);
        (bool ok,) = address(bank).call{value: amount}("");
        require(ok, "fund bank failed");
    }
}
