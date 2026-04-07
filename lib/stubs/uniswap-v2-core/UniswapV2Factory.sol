// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/// @dev Resolves `@uniswap/v2-core/UniswapV2Factory.sol` for IDEs. Real deployment uses
///      `lib/uniswap-artifacts/UniswapV2Factory.json` via `UniswapArtifactLib`.
contract UniswapV2Factory {
    address public feeTo;
    address public feeToSetter;
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address, address) external pure returns (address) {
        revert("stub: use UniswapArtifactLib + artifacts");
    }

    function setFeeTo(address) external pure {
        revert("stub");
    }

    function setFeeToSetter(address) external pure {
        revert("stub");
    }
}
