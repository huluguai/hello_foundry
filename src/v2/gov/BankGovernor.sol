// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Bank} from "../../Bank.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";

/// @title BankGovernor
/// @notice 通过治理提案管理 Bank.withdraw() 的执行。
contract BankGovernor is Governor, GovernorSettings, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {
    Bank public immutable bank;

    constructor(IVotes token)
        Governor("BankGovernor")
        GovernorSettings(1, 10, 0)
        GovernorVotes(token)
        GovernorVotesQuorumFraction(4)
    {
        bank = new Bank();
    }

    receive() external payable override {}

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function quorum(uint256 timepoint) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(timepoint);
    }
}
