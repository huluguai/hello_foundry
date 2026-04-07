// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Simple ERC20 for dual-pool flash arbitrage demos; full supply minted to `recipient`.
contract MyToken is ERC20 {
    constructor(string memory name_, string memory symbol_, address recipient, uint256 initialSupply)
        ERC20(name_, symbol_)
    {
        _mint(recipient, initialSupply);
    }
}
