// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NFTMarketUpgradeableV1} from "../src/v2/mynft/upgradeable/NFTMarketUpgradeableV1.sol";

/**
 * @title DeployUpgradeableNFTMarket
 * @notice 部署与 `NFTMarketV2.sol` 中 `NFTMarket` 逻辑对齐的 UUPS 可升级市场：V1 实现 + `ERC1967Proxy`。
 * @dev
 * - **用户 / NFT / ERC20 交互地址**：始终使用下方日志中的 **Proxy** 地址（`delegatecall` 到当前实现）。
 * - **实现合约地址**：仅用于升级验证或审计；不要对用户展示为「市场合约」。
 * - `initialize` 在代理 **构造参数** 里执行一次，写入支付币、`whitelistSigner`（签发 `PermitBuy`）、`owner`（可执行 `upgradeToAndCall`、`setWhitelistSigner`）。
 * - 升级到 V2（`listWithSig`）：部署完成后另跑 `UpgradeNFTMarketToV2.s.sol`，并设置 `NFT_MARKET_PROXY` 为本次 Proxy 地址。
 *
 * 环境变量：
 * - `PRIVATE_KEY`：部署者私钥（uint）；
 * - `PAYMENT_TOKEN_ADDRESS`：支付用 ERC20（需 `decimals()`，不可为 0 地址）；
 * - `WHITELIST_SIGNER`：可选，签发购买侧 EIP-712 `PermitBuy` 的地址；未设时默认为部署者。
        NFTMarketProxy (use this address): 0xDDae7D607bB335093144EC1aEA1671A3b59E9d55
        NFTMarketUpgradeableV1 implementation: 0x7aA18BBA80593D3f0ced5f190D82b43cDCc38974
        Owner: 0xfd8890Be36244f4270602B1F46717882c5ffDf47
        Payment token: 0x5256Db529A2AD34077bFC0F8b0c288df58AeB654
        Whitelist signer: 0xfd8890Be36244f4270602B1F46717882c5ffDf47
 *
 * 示例（Sepolia）：
 * `forge script script/DeployUpgradeableNFTMarket.s.sol:DeployUpgradeableNFTMarket --rpc-url sepolia --broadcast --verify -vvvv`
 */
contract DeployUpgradeableNFTMarket is Script {
    function run() public {
        // 部署者：同时作为 `initialize(..., initialOwner)` 的初始 owner
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // 市场计价/结算代币，须与运行时 `list` / `permitBuy` 使用的代币一致
        address paymentToken = vm.envAddress("PAYMENT_TOKEN_ADDRESS");
        // 购买路径 `permitBuy` / `tokensReceived` 校验的链下签名人（非上架签名者）
        address whitelistSigner = vm.envOr("WHITELIST_SIGNER", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 逻辑实现：单独部署；代理通过 ERC-1967 槽位指向它，之后可被 owner 换为 V2 实现
        NFTMarketUpgradeableV1 impl = new NFTMarketUpgradeableV1();
        // 代理创建时在 delegatecall 上下文中调用 `initialize`，完成可升级合约的状态初始化
        bytes memory init = abi.encodeCall(NFTMarketUpgradeableV1.initialize, (paymentToken, whitelistSigner, deployer));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);

        vm.stopBroadcast();

        console.log("NFTMarketProxy (use this address):", address(proxy));
        console.log("NFTMarketUpgradeableV1 implementation:", address(impl));
        console.log("Owner:", deployer);
        console.log("Payment token:", paymentToken);
        console.log("Whitelist signer:", whitelistSigner);
    }
}
