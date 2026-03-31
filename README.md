# hello_foundry

基于 [Foundry](https://book.getfoundry.sh/) 的 Solidity 学习与实验仓库：ERC20 金库（含 EIP-2612 与 [Permit2](https://github.com/Uniswap/permit2)）、以及 ERC20 支付 + EIP-712 白名单的 NFT 市场示例。

## 依赖

- [forge-std](https://github.com/foundry-rs/forge-std)
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [OpenZeppelin Contracts Upgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable)（`lib/openzeppelin-contracts-upgradeable`，与主库 v5.6 配套）
- [Uniswap Permit2](https://github.com/Uniswap/permit2)（`permit2/` remapping）

克隆后若子模块未就绪：

```shell
git submodule update --init --recursive
```

## 主要合约（`src/`）

| 路径 | 说明 |
|------|------|
| `v2/mytoken/token_bank_v2.sol` — **TokenBankV2** | 标准 `deposit` / `withdraw`；**EIP-2612** 离线授权由第三方代调的 `permitDeposit`；**Permit2 Allowance Transfer** 的 `depositWithPermit2`（需先对 Permit2 合约 `approve` 代币） |
| `v2/mytoken/xzx_token.sol` — **XZXToken** | 带 `ERC20Permit` 的示例代币，部署脚本用于与 TokenBankV2 联署 |
| `v2/mynft/NFTMarketV2.sol` — **NFTMarket** | 上架 / 下架；买家通过 `permitBuy` 或 `transferWithCallback`（`ITokenRecipient`）完成 ERC20 支付，购买需 EIP-712 白名单签名 |
| `v2/mynft/upgradeable/NFTMarketUpgradeableV1.sol` / `NFTMarketUpgradeableV2.sol` | 与 **NFTMarket** 对齐的 **UUPS 可升级**市场；V2 增加卖家签名 `listWithSig`（`PermitList` EIP-712，含 `seller/nftContract/tokenId/price/nonce/deadline`）；用户交互地址为 **代理** |
| `v2/mynft/upgradeable/MyURINFTUpgradeable.sol` | **UUPS 可升级** ERC721 + URIStorage + 可治理升级 |
| `v2/mynft/AirdopMerkleNFTMarket.sol` — **AirdopMerkleNFTMarket** | 上架 / 下架；**Merkle 白名单**折后购（`multicall` + `permitPrePay` + `claimNFT`，支付为 `ERC20Permit`）或原价 `buyNFT`；详见下文「默克尔白名单」 |
| `v2/mynft/MyBasicNFT.sol` | 简单 ERC721，供市场测试使用 |

历史/其他示例：`Counter.sol`、`Bank.sol`、`TokenBank.sol`、`NFT_Market.sol` 等。

## 测试（`test/`）

- `TokenBankV2PermitTest.sol` — EIP-2612 `permitDeposit`
- `TokenBankV2Permit2Test.sol` — Permit2 `depositWithPermit2`（含 `mocks/MockPermit2.sol`）
- `NFTMarketV2Test.sol` — 市场与白名单购买流程
- `NFTMarketUpgradeable.t.sol` — 可升级市场代理、`upgradeTo` V2、`listWithSig` 与 `permitBuy` / `transferWithCallback`
- `MyURINFTUpgradeable.t.sol` — 可升级 ERC721 与升级权限
- `AirdopMerkleNFTMarket.t.sol` — Merkle 白名单 + multicall + Permit 折后购与相关边界情况

## 文档

- [TokenBankV2：Permit、Gas 与 Relayer 说明](docs/permit-gas-relayer.md)
- [AirdopMerkleNFTMarket：DApp 调用关系与时序](docs/AirdopMerkleNFTMarket-dapp-callflow.md)
- [可升级 NFT 与市场：升级后调用关系与说明](docs/UpgradeableNFTMarket.md)

## 默克尔白名单（`AirdopMerkleNFTMarket`）

链上只存储 **Merkle 根** `merkleRoot`；某个地址是否在白名单，由 **叶子 + 证明** 在链上复算是否等于该根来决定。实现与 [`src/v2/mynft/AirdopMerkleNFTMarket.sol`](src/v2/mynft/AirdopMerkleNFTMarket.sol) 中 `MerkleProof.verifyCalldata` 一致。

### 树的构建（链下）

1. **叶子**（必须与合约完全一致，一字节不能差）  
   `leaf = keccak256(abi.encodePacked(用户地址))`  
   每个白名单地址对应一个 `bytes32` 叶子。

2. **只有一个地址时**：根就是该叶子，`proof` 可为空数组 `[]`。

3. **多个叶子时**：自下而上两两归约成父节点。本项目使用 OpenZeppelin `MerkleProof`，内部对每层兄弟使用 **`Hashes.commutativeKeccak256`**（对两个 `bytes32` 排序后再 `keccak256(abi.encode(a,b))`），与 [@openzeppelin/merkle-tree](https://github.com/OpenZeppelin/merkle-tree) 等标准建树方式一致。

4. 归约得到唯一 **`merkleRoot`**，部署时写入合约或由 owner `setMerkleRoot` 更新。

建议在链外用官方/成熟库建树并发证明，避免手算顺序或编码错误。

### 用户如何「验证自己在不在白名单」

- **链下**：项目方根据完整名单为每个地址生成 **`proof`**（从该叶子到根路径上的兄弟哈希序列）。用户通过 DApp/API 用当前钱包地址领取自己的 `proof`（或从静态表里查）。单靠地址、没有 `proof` 和链上 `merkleRoot`，无法在本地「证出」成员身份。
- **链上**：用户调用 `claimNFT(listingId, proof)` 时（须在 `multicall` 内），合约用 **`msg.sender`** 计算 `leaf = keccak256(abi.encodePacked(msg.sender))`，再执行 `MerkleProof.verifyCalldata(proof, merkleRoot, leaf)`。通过则表示在当前根下该地址被视为白名单成员；否则 `NotWhitelisted`。

**注意**：Merkle 证明是**成员性证明**，不是隐私名单；他人若知道你的地址与叶子规则，可推断你的叶子形式。

## 配置

- Solidity：`0.8.24`（见 `foundry.toml`）
- Remappings：`@openzeppelin/contracts-upgradeable/`、`@openzeppelin/contracts/`、`@openzeppelin/`、`permit2/`（见 `foundry.toml`）
- 根目录 `.env` 供 Foundry 替换变量：`RPC_URL`、`ETHERSCAN_API_KEY` 等（勿提交私钥到公开仓库）

部署脚本常用环境变量：

| 变量 | 用途 |
|------|------|
| `PRIVATE_KEY` | 部署者私钥（uint） |
| `INITIAL_SUPPLY` | `DeployTokenBankV2` 中 XZXToken 初始发行量（整币数量，默认 `1000000`） |
| `PAYMENT_TOKEN_ADDRESS` | `DeployNFTMarketV2` 支付用 ERC20（需 `decimals()`） |
| `WHITELIST_SIGNER` | 签发 `PermitBuy` 的地址；未设时默认为部署者地址 |
| `NFT_MARKET_PROXY` | `UpgradeNFTMarketToV2`：已部署的市场 **代理**地址 |
| `NFT_NAME` / `NFT_SYMBOL` | `DeployUpgradeableMyURINFT` 可选，默认 `MyURINFT` / `MUN` |

链上 Permit2 在 Ethereum / Sepolia 等与官方部署同址：`0x000000000022D473030F116dDEE9F6B43aC78BA3`（脚本内常量）。

### 可升级 NFT 与市场（Sepolia）

部署后把下列地址写进本表并在浏览器上开源验证（代理需在 Etherscan 「Read/Write as Proxy」中指向当前实现）。

| 角色 | 地址（待部署后填写） |
|------|----------------------|
| NFT 市场 **代理**（对外使用） | `0xDDae7D607bB335093144EC1aEA1671A3b59E9d55` |
| 市场实现 **V1** | `0x7aA18BBA80593D3f0ced5f190D82b43cDCc38974` |
| 市场实现 **V2** | `0xD9FC5ced60E7b0D89CCe17004D289490dC16b91B` |
| MyURINFT **代理**（可选） | `0xC1D05b658336f1A3A6d2233524C8e9c1C326171f` |
| MyURINFT **实现**（可选） | `0xc5411e6c21B8330d51F567a3E619772684729e97` |

浏览器示例：`https://sepolia.etherscan.io/address/<REPLACE_WITH_PROXY>#code`

部署市场（V1 实现 + 代理，`PAYMENT_TOKEN_ADDRESS` 必填）：

```shell
source .env && forge script script/DeployUpgradeableNFTMarket.s.sol:DeployUpgradeableNFTMarket --rpc-url sepolia --broadcast --verify -vvvv
```

升级至 V2（`PRIVATE_KEY` 须为代理的 `owner`）：

```shell
export NFT_MARKET_PROXY=0xDDae7D607bB335093144EC1aEA1671A3b59E9d55
source .env && forge script script/UpgradeNFTMarketToV2.s.sol:UpgradeNFTMarketToV2 --rpc-url sepolia --broadcast --verify -vvvv
```

部署可升级 ERC721：

```shell
source .env && forge script script/DeployUpgradeableMyURINFT.s.sol:DeployUpgradeableMyURINFT --rpc-url sepolia --broadcast --verify -vvvv
```

单独验证实现合约（示例）：

```shell
forge verify-contract <IMPL> src/v2/mynft/upgradeable/NFTMarketUpgradeableV2.sol:NFTMarketUpgradeableV2 --chain sepolia --watch
```

## 常用命令

```shell
forge build
forge test
forge fmt
```

部署并验证（示例：Sepolia，需已配置 `foundry.toml` 中 `[rpc_endpoints]` / `[etherscan]` 与 `.env`）：

```shell
source .env && forge script script/DeployTokenBankV2.s.sol:DeployTokenBankV2 --rpc-url sepolia --broadcast --verify -vvvv
```

```shell
source .env && forge script script/DeployNFTMarketV2.s.sol:DeployNFTMarketV2 --rpc-url sepolia --broadcast --verify -vvvv
```

也可将 `--rpc-url sepolia` 换成 `"$RPC_URL"` 等显式 RPC。

---

## Foundry 工具简介

Foundry 提供 **Forge**（测试）、**Cast**（链上交互）、**Anvil**（本地节点）、**Chisel**（Solidity REPL）。完整文档：<https://book.getfoundry.sh/>

### Gas 快照

```shell
forge snapshot
```

### 本地节点

```shell
anvil
```

### Cast / 帮助

```shell
cast --help
forge --help
```
