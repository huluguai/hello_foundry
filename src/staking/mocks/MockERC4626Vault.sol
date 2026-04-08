// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @notice 测试/本地部署用 ERC4626；可向合约直接转 `asset` 模拟借贷利息。
contract MockERC4626Vault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Mock Vault Share", "mvSHARE") ERC4626(asset_) {}
}
