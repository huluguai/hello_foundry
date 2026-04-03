// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {TokenVesting} from "../src/v2/vesting/TokenVesting.sol";

/**
 * @title DeployTokenVesting
 * @notice 部署 `TokenVesting`：受益人、ERC20 与 cliff/线性时长由环境变量配置；`start` 为部署所在区块的 `block.timestamp`。
 * @dev 部署后需自行向 Vesting 合约 `transfer` 代币（例如 100 万枚 * 精度）。
 *
 * 环境变量：
 * | 变量 | 必填 | 说明 |
 * |------|------|------|
 * | PRIVATE_KEY | 是 | 部署账户私钥 |
 * | VESTING_BENEFICIARY | 是 | 受益人地址 |
 * | VESTING_TOKEN | 是 | 被锁仓的 ERC20 合约地址 |
 * | VESTING_CLIFF_SECONDS | 否 | cliff 秒数；默认 `12 * 30 days` |
 * | VESTING_LINEAR_SECONDS | 否 | 线性段秒数；默认 `24 * 30 days` |
 *
 * 示例（Sepolia）：
 * `VESTING_BENEFICIARY=0x... VESTING_TOKEN=0x... forge script script/DeployTokenVesting.s.sol:DeployTokenVesting --rpc-url sepolia --broadcast -vvvv`
 */
contract DeployTokenVesting is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address beneficiary = vm.envAddress("VESTING_BENEFICIARY");
        address token = vm.envAddress("VESTING_TOKEN");

        uint64 cliff = uint64(vm.envOr("VESTING_CLIFF_SECONDS", uint256(12 * 30 days)));
        uint64 linear = uint64(vm.envOr("VESTING_LINEAR_SECONDS", uint256(24 * 30 days)));

        vm.startBroadcast(deployerPrivateKey);

        uint64 startTs = uint64(block.timestamp);
        TokenVesting v = new TokenVesting(beneficiary, token, startTs, cliff, linear);

        vm.stopBroadcast();

        console.log("TokenVesting deployed at:", address(v));
        console.log("Beneficiary:", v.beneficiary());
        console.log("Token:", address(v.token()));
        console.log("Start (unix):", v.start());
        console.log("Cliff duration (s):", uint256(v.cliffDuration()));
        console.log("Linear duration (s):", uint256(v.linearDuration()));
        console.log("Cliff end (unix):", v.cliffEnd());
        console.log("Vesting end (unix):", v.vestingEnd());
        console.log("Deployer:", deployer);
    }
}
