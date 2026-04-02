// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MemeFactory} from "../src/v2/meme/MemeFactory.sol";

/**
 * @title DeployMemeFactory
 * @notice Foundry 脚本：部署 Meme 发射工厂 `MemeFactory`。
 * @dev
 * - `MemeFactory` 构造函数内部会执行 `new MemeToken(address(this))`，因此**同一笔链上交易**中会得到：
 *   1）工厂合约地址；2）`MemeToken` 逻辑实现地址（`factory.implementation()`）。
 * - 之后用户通过 `factory.deployMeme(...)` 克隆的是该实现，Gas 远低于每次完整部署 ERC20。
 * - 项目方地址 `projectRecipient` 接收的是 **Uniswap V2 LP**（`addLiquidityETH` 的 `to`），铸造费 ETH 的 5% 与同比例代币进入池子，不向该地址直接转 ETH。
 * - **UNISWAP_V2_ROUTER**：目标链上 Uniswap V2 `Router02` 合约地址（必填）。
 *
 * 环境变量（建议在项目根目录 `.env` 中配置，Foundry 会自动加载）：
 * | 变量 | 必填 | 说明 |
 * |------|------|------|
 * | PRIVATE_KEY | 是 | 部署账户私钥（uint256，无前缀 0x 亦可由 forge 解析） |
 * | PROJECT_RECIPIENT | 否 | 项目方地址；未设置时默认为部署者地址 |
 * | UNISWAP_V2_ROUTER | 是 | Uniswap V2 Router02 地址 |
 * | RPC_URL | 视命令而定 | 与 `foundry.toml` 里 `[rpc_endpoints] sepolia` 等配合使用 |
 * | ETHERSCAN_API_KEY | 使用 --verify 时需要 | 区块浏览器 API Key，用于合约源码验证 |
 *
 * 常用命令示例：
 * - 本地 Anvil：
 *   `forge script script/DeployMemeFactory.s.sol:DeployMemeFactory --rpc-url http://127.0.0.1:8545 --broadcast`
 * - Sepolia 部署并验证工厂：
 *   `source .env && forge script script/DeployMemeFactory.s.sol:DeployMemeFactory --rpc-url sepolia --broadcast --verify -vvvv`
 * - 显式指定项目方与 Router：
 *   `PROJECT_RECIPIENT=0x... UNISWAP_V2_ROUTER=0x... forge script ... --rpc-url sepolia --broadcast`
 */
contract DeployMemeFactory is Script {
    /**
     * @notice 脚本入口：`forge script` 默认调用 `run()`。
     * @dev 使用 `vm.startBroadcast` / `stopBroadcast` 包裹实际部署，以便生成可广播的交易（`--broadcast`）。
     */
    function run() public {
        // 从环境读取部署私钥；缺失或非法时 forge 会报错退出
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address projectRecipient = vm.envOr("PROJECT_RECIPIENT", deployer);
        address uniswapV2Router = vm.envAddress("UNISWAP_V2_ROUTER");

        vm.startBroadcast(deployerPrivateKey);

        MemeFactory factory = new MemeFactory(projectRecipient, uniswapV2Router);

        vm.stopBroadcast();

        // 广播后可在终端与 broadcast/*.json 中对照地址
        console.log("MemeFactory deployed at:", address(factory));
        console.log("MemeToken implementation:", factory.implementation());
        console.log("Project recipient (LP receiver):", factory.projectRecipient());
        console.log("Uniswap V2 Router:", address(factory.uniswapRouter()));
        console.log("Deployer:", deployer);
    }
}
