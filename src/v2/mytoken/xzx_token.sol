// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title XZXToken
 * @dev ERC20 with EIP-2612 permit via OpenZeppelin. Name "xzx" matches ERC20Permit EIP-712 domain.
 */
contract XZXToken is ERC20Permit {
    /**
     * @param initialSupplyWholeTokens 初始供应量（整币单位，内部按 decimals 转为最小单位）
     */
    constructor(uint256 initialSupplyWholeTokens) ERC20("xzx", "XZX") ERC20Permit("xzx") {
        _mint(msg.sender, initialSupplyWholeTokens * (10 ** decimals()));
    }
}
