// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";

/// @dev Deploy contracts from `lib/uniswap-artifacts/*.json` (bytecode field).
library UniswapArtifactLib {
    function deployFromArtifact(Vm vm, string memory relPath, bytes memory constructorArgs)
        internal
        returns (address addr)
    {
        string memory json = vm.readFile(string.concat("lib/uniswap-artifacts/", relPath));
        bytes memory bytecode = vm.parseJsonBytes(json, ".bytecode");
        bytes memory payload = abi.encodePacked(bytecode, constructorArgs);
        assembly ("memory-safe") {
            addr := create(0, add(payload, 0x20), mload(payload))
        }
        require(addr != address(0), "artifact deploy failed");
    }
}
