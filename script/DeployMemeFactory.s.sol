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
 * - 铸造费 1% 的收款方为构造参数 `projectRecipient`（见 `MemeFactory` 合约注释）。
 *
 * 环境变量（建议在项目根目录 `.env` 中配置，Foundry 会自动加载）：
 * | 变量 | 必填 | 说明 |
 * |------|------|------|
 * | PRIVATE_KEY | 是 | 部署账户私钥（uint256，无前缀 0x 亦可由 forge 解析） |
 * | PROJECT_RECIPIENT | 否 | 项目方 ETH 收款地址；未设置时默认为部署者地址，便于本地/测试网试跑 |
 * | RPC_URL | 视命令而定 | 与 `foundry.toml` 里 `[rpc_endpoints] sepolia` 等配合使用 |
 * | ETHERSCAN_API_KEY | 使用 --verify 时需要 | 区块浏览器 API Key，用于合约源码验证 |
 *
 * 常用命令示例：
 * - 本地 Anvil：
 *   `forge script script/DeployMemeFactory.s.sol:DeployMemeFactory --rpc-url http://127.0.0.1:8545 --broadcast`
 * - Sepolia 部署并验证工厂：
 *   `source .env && forge script script/DeployMemeFactory.s.sol:DeployMemeFactory --rpc-url sepolia --broadcast --verify -vvvv`
 * - 显式指定项目方地址（可与部署者不同）：
 *   `PROJECT_RECIPIENT=0x... forge script ... --rpc-url sepolia --broadcast`
 
    MemeFactory deployed at: 0xe59a723aB198aF185c970957386faf4e27cBAd63
    MemeToken implementation: 0x8f628fcB6986aBDe79b0a1952d573c9364ae22E3
    Project recipient (1% fees): 0xfd8890Be36244f4270602B1F46717882c5ffDf47
    Deployer: 0xfd8890Be36244f4270602B1F46717882c5ffDf47
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

        // 项目方 1% 铸造费收款地址；不设则与部署者相同（测试时常用）
        address projectRecipient = vm.envOr("PROJECT_RECIPIENT", deployer);

        // 后续 `new` 发出的交易由 deployer 签名并广播
        vm.startBroadcast(deployerPrivateKey);

        MemeFactory factory = new MemeFactory(projectRecipient);

        vm.stopBroadcast();

        // 广播后可在终端与 broadcast/*.json 中对照地址
        console.log("MemeFactory deployed at:", address(factory));
        console.log("MemeToken implementation:", factory.implementation());
        console.log("Project recipient (1% fees):", factory.projectRecipient());
        console.log("Deployer:", deployer);
    }
}
