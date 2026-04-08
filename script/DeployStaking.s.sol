// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {StakingPool} from "../src/staking/StakingPool.sol";
import {KKToken} from "../src/staking/KKToken.sol";
import {IWETH} from "../src/staking/interfaces/IWETH.sol";
import {MockWETH} from "../src/staking/mocks/MockWETH.sol";
import {MockERC4626Vault} from "../src/staking/mocks/MockERC4626Vault.sol";

/**
 * @title DeployStaking
 * @notice 部署 `KKToken` + `StakingPool`。若未提供 `STAKING_WETH` / `STAKING_VAULT`，则自动部署测试用 Mock WETH 与 Mock ERC4626 金库。
 *
 * 环境变量：
 * | 变量 | 必填 | 说明 |
 * |------|------|------|
 * | PRIVATE_KEY | 是 | 部署账户私钥 |
 * | STAKING_WETH | 否 | WETH 地址；缺省或 `address(0)` 时部署 `MockWETH` |
 * | STAKING_VAULT | 否 | ERC4626 金库地址，且 `asset()` 须为上述 WETH；缺省或零地址时部署 `MockERC4626Vault` |
 * | STAKING_REWARD_PER_BLOCK | 否 | 每块 KK 释放量（wei），默认 `10 * 10**18` |
 *
 * 部署后步骤（由本脚本执行）：`KKToken.setStakingPool(StakingPool)`。
 *
 * 示例（本地 Anvil，全 Mock）：
 * `forge script script/DeployStaking.s.sol:DeployStaking --rpc-url http://127.0.0.1:8545 --broadcast -vvvv`
 */
contract DeployStaking is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 rewardPerBlock = vm.envOr("STAKING_REWARD_PER_BLOCK", uint256(10e18));

        vm.startBroadcast(deployerPrivateKey);

        address wethAddr = vm.envOr("STAKING_WETH", address(0));
        if (wethAddr == address(0)) {
            wethAddr = address(new MockWETH());
            console.log("Deployed MockWETH at:", wethAddr);
        }

        address vaultAddr = vm.envOr("STAKING_VAULT", address(0));
        if (vaultAddr == address(0)) {
            vaultAddr = address(new MockERC4626Vault(IERC20(wethAddr)));
            console.log("Deployed MockERC4626Vault at:", vaultAddr);
        }

        // 步骤 1：部署 KK，owner 为部署者，用于一次性 `setStakingPool`。
        KKToken kk = new KKToken(deployer);
        // 步骤 2：部署质押池（构造函数内校验 `vault.asset() == weth`）。
        StakingPool pool = new StakingPool(IWETH(wethAddr), IERC4626(vaultAddr), kk, rewardPerBlock);
        // 步骤 3：绑定 minter，仅质押池可铸造 KK 奖励。
        kk.setStakingPool(address(pool));

        vm.stopBroadcast();

        console.log("KKToken:", address(kk));
        console.log("StakingPool:", address(pool));
        console.log("WETH:", wethAddr);
        console.log("Vault:", vaultAddr);
        console.log("rewardPerBlock:", rewardPerBlock);
        console.log("Deployer:", deployer);
    }
}
