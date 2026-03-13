// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITokenRecipient - Interface for contracts receiving tokens via hooks
 * @dev Similar to ERC777 tokensReceived but simplified
 */
interface ITokenRecipient {
    /**
     * @notice Called when tokens are received via transferWithCallback
     * @param from The sender of tokens
     * @param to The recipient address (this contract)
     * @param amount Amount transferred (in smallest units)
     * @param data Additional data passed through
     * @return bool Success status
     */
    function tokensReceived(       
        address from,
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}