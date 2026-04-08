// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title KKToken
/// @notice 质押挖矿奖励代币；仅已绑定的 `StakingPool` 可 `mint`（部署后由 owner 调用 `setStakingPool` 一次性绑定）。
/// @dev 部署顺序：`KKToken(deployer)` -> `StakingPool(..., kk, ...)` -> `kk.setStakingPool(pool)`。
contract KKToken is ERC20, Ownable {
    address public stakingPool;

    constructor(address initialOwner) ERC20("KK Token", "KK") Ownable(initialOwner) {}

    /// @notice 绑定质押池地址；只能设置一次，且不能为零地址。
    function setStakingPool(address pool) external onlyOwner {
        require(stakingPool == address(0) && pool != address(0), "KKToken: pool already set or zero");
        stakingPool = pool;
    }

    /// @notice 由 `StakingPool` 铸造奖励给用户。
    function mint(address to, uint256 amount) external {
        require(msg.sender == stakingPool, "KKToken: only staking pool");
        _mint(to, amount);
    }
}
