// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/**
 * @dev 测试用 Permit2 替身：不验 EIP-712，仅模拟 permit + transferFrom 额度与 ERC20 拉取。
 *      用户需对本合约执行 token.approve(mock, amount)。
 */
contract MockPermit2 {
    mapping(address owner => mapping(address tokenAddr => mapping(address spender => uint48 nonce))) public nonces;

    mapping(address owner => mapping(address tokenAddr => mapping(address spender => uint160 allowance))) internal
        _allowance;

    function permit(address owner, IAllowanceTransfer.PermitSingle calldata permitSingle, bytes calldata) external {
        require(owner != address(0), "owner zero");
        address tokenAddr = permitSingle.details.token;
        address spender = permitSingle.spender;
        require(block.timestamp <= permitSingle.sigDeadline, "sig expired");
        require(block.timestamp <= permitSingle.details.expiration, "allowance expired");
        require(permitSingle.details.nonce == nonces[owner][tokenAddr][spender], "bad nonce");
        nonces[owner][tokenAddr][spender] = permitSingle.details.nonce + 1;
        _allowance[owner][tokenAddr][spender] = permitSingle.details.amount;
    }

    function transferFrom(address from, address to, uint160 amount, address tokenAddr) external {
        address spender = msg.sender;
        uint160 a = _allowance[from][tokenAddr][spender];
        require(a >= amount, "insufficient permit2 allowance");
        unchecked {
            _allowance[from][tokenAddr][spender] = a - amount;
        }
        require(IERC20(tokenAddr).transferFrom(from, to, amount), "transferFrom failed");
    }
}
