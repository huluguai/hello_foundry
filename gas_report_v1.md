# NFTMarket（NFTMarketV2.sol）Gas 报告 v1

- **生成方式**: `forge test --match-contract NFTMarketV2Test --gas-report`
- **环境**: Foundry，`NFTMarketV2Test`（`test/NFTMarketV2Test.sol`），23 个用例全部通过
- **合约**: `src/v2/mynft/NFTMarketV2.sol`（合约名 `NFTMarket`）

---

## 1. NFTMarket 部署

| 项目 | 数值 |
|------|------|
| Deployment Cost | 3,138,243 |
| Deployment Size | 17,177 bytes |

---

## 2. NFTMarket 对外函数（`--gas-report` 汇总）

表中为测试套件内对该函数的 **Min / Avg / Median / Max** 与调用次数。**注意**: 实际测试中的总 gas 还包含 ERC20/ERC721 的 `approve`、`transferFrom` 等外围调用；下表为 Foundry 对该合约入口的统计。

| Function | Min | Avg | Median | Max | # Calls |
|----------|-----|-----|--------|-----|---------|
| `buyNFT` | 628 | 628 | 628 | 628 | 1 |
| `getPriceInTokenUnits` | 3,444 | 3,444 | 3,444 | 3,444 | 1 |
| `list` | 22,663 | 159,976 | 188,781 | 192,890 | 22 |
| `listings`（public getter） | 11,840 | 11,840 | 11,840 | 11,840 | 5 |
| `nextListingId` | 2,514 | 2,514 | 2,514 | 2,514 | 1 |
| `permitBuy` | 26,457 | 54,981 | 32,786 | 120,129 | 8 |
| `setWhitelistSigner` | 30,436 | 30,436 | 30,436 | 30,436 | 1 |
| `unlist` | 24,164 | 27,609 | 26,338 | 32,327 | 3 |
| `whitelistSigner` | 2,552 | 2,552 | 2,552 | 2,552 | 1 |

**说明**

- `list` 的 Min 明显低于 Median/Max：部分路径为 **`test_List_RevertWhen_*` 等失败用例**，较早 `revert`，故拉低最小值；成功上架约在 **~189k** 量级（见 Median/Max）。
- `permitBuy` 同理：含成功购买与多种 `revert` 分支；成功路径可参考 **Max ~120k** 附近的完整购买（仍不含测试里单独的 `token.approve` 等）。
- **`tokensReceived`** 未单独出现在上表：测试中仅由 `MyTokenV2.transferWithCallback` 在回调里调用，Foundry 将其计入代币合约的 `transferWithCallback` 调用统计；购买+回调整体可参考下方 **MyTokenV2** 与 **整测 gas**。

---

## 3. 相关依赖合约（同次 `gas-report`）

### MyURINFT（`MyBasicNFT.sol`）

- Deployment Cost: 2,289,295；Size: 11,314

| Function | Min | Avg | Median | Max | # Calls |
|----------|-----|-----|--------|-----|---------|
| `approve` | 49,001 | 49,009 | 49,013 | 49,013 | 19 |
| `mint` | 104,530 | 104,530 | 104,530 | 104,530 | 23 |
| （其余略，见终端完整输出） | | | | | |

### XZXToken（`permitBuy` 路径）

- Deployment Cost: 1,713,194；Size: 10,865

| Function | Min | Avg | Median | Max | # Calls |
|----------|-----|-----|--------|-----|---------|
| `approve` | 46,942 | 46,942 | 46,942 | 46,942 | 9 |
| `decimals` | 427 | 427 | 427 | 427 | 24 |
| `transfer` | 52,172 | 52,172 | 52,172 | 52,172 | 23 |

### MyTokenV2（`tokensReceived` / `transferWithCallback` 路径）

- Deployment Cost: 2,529,767；Size: 13,332

| Function | Min | Avg | Median | Max | # Calls |
|----------|-----|-----|--------|-----|---------|
| `transferWithCallback` | 62,804 | 115,709 | 139,913 | 144,648 | 5 |

---

## 4. 各测试用例整笔 gas（`forge test` 单行输出）

以下为 **`test/NFTMarketV2Test`** 中每个测试的 **approximate gas**（含 setUp 中与该测相关的所有调用）。

| 测试 | Gas |
|------|-----|
| `test_BuyNFT_Reverts` | 319,387 |
| `test_Invariant_MarketHoldsNoTokens` | 6,591,539 |
| `test_List_ByApprovedOperator` | 279,016 |
| `test_List_RevertWhen_AlreadyListed` | 296,357 |
| `test_List_RevertWhen_NotOwner` | 55,268 |
| `test_List_RevertWhen_ZeroNftContract` | 94,158 |
| `test_List_RevertWhen_ZeroPrice` | 92,614 |
| `test_List_Success` | 306,987 |
| `test_PermitBuy_RevertWhen_BuyerMismatchInSignature` | 354,582 |
| `test_PermitBuy_RevertWhen_ExpiredDeadline` | 347,902 |
| `test_PermitBuy_RevertWhen_InsufficientAmount` | 370,445 |
| `test_PermitBuy_RevertWhen_NotListed` | 105,103 |
| `test_PermitBuy_RevertWhen_SignerZero` | 3,494,632 |
| `test_PermitBuy_RevertWhen_WrongSigner` | 352,290 |
| `test_PermitBuy_Success` | 455,690 |
| `test_SetWhitelistSigner` | 44,077 |
| `test_TransferWithCallback_BuySuccess` | 6,207,635 |
| `test_TransferWithCallback_RefundExcess` | 6,212,225 |
| `test_TransferWithCallback_RevertWhen_InsufficientAmount` | 6,154,861 |
| `test_TransferWithCallback_RevertWhen_InvalidDataDecode` | 6,121,232 |
| `test_Unlist_RevertWhen_NotListed` | 35,413 |
| `test_Unlist_RevertWhen_NotLister` | 289,240 |
| `test_Unlist_Success` | 302,425 |

**说明**: `test_TransferWithCallback_*`、`test_Invariant_*`、`test_PermitBuy_RevertWhen_SignerZero` 等数值较大，主要因为用例内 **`new MyTokenV2` / `new NFTMarket`** 等额外部署与多步交互。

---

## 5. 如何复现

在项目根目录执行：

```bash
forge test --match-contract NFTMarketV2Test --gas-report
```
