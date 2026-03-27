# NFTMarket（NFTMarketV2.sol）Gas 报告 v2（优化后）

- **生成方式**: `forge test --match-contract NFTMarketV2Test --gas-report`
- **环境**: Foundry，`NFTMarketV2Test`，23 个用例全部通过
- **相对 v1 的合约改动摘要**:
  - 全部 `require("...")` 改为 **`error` + `revert`**，缩短 runtime revert 数据并减小部署体积
  - 构造函数中计算并 **`immutable tokenUnit`**（`10 ** decimals`），`list` / `permitBuy` / `getPriceInTokenUnits` / 回调路径不再每次做幂运算
  - `nextListingId` 递增放入 **`unchecked`**（业务上不可能溢出）
  - `activeListingByNft` 的 key：在 **`unlist`、`_executePurchaseDirect`、`_executePurchaseCallback`** 中对 `keccak256(abi.encode(nft, tokenId))` **只算一次** 复用
  - **`_verifyPermitBuy`**：`ECDSA.recover` 结果直接与 `whitelistSigner` 比较，避免中间 `address recovered` 变量（微小节省）
  - **`_executePurchaseCallback`**：缓存 `l.priceInWei`、合并超额退款计算为单次除法

---

## 1. NFTMarket 部署（对比 v1）

| 项目 | v1 | v2 | 差值 |
|------|-----|-----|------|
| Deployment Cost | 3,138,243 | 2,690,232 | **−448,011** |
| Deployment Size (bytes) | 17,177 | 14,986 | **−2,191** |

> 部署成本下降主要来自自定义 `error` 替代长字符串 revert 元数据及略紧凑的逻辑路径。

---

## 2. NFTMarket 对外函数（`--gas-report` 汇总）

| Function | Min | Avg | Median | Max | # Calls |
|----------|-----|-----|--------|-----|---------|
| `buyNFT` | 628 | 628 | 628 | 628 | 1 |
| `getPriceInTokenUnits` | 2,976 | 2,976 | 2,976 | 2,976 | 1 |
| `list` | 22,414 | 159,450 | 188,193 | 192,302 | 22 |
| `listings` | 11,840 | 11,840 | 11,840 | 11,840 | 5 |
| `nextListingId` | 2,514 | 2,514 | 2,514 | 2,514 | 1 |
| `permitBuy` | 26,208 | 54,618 | 32,535 | 119,664 | 8 |
| `setWhitelistSigner` | 30,436 | 30,436 | 30,436 | 30,436 | 1 |
| `unlist` | 23,915 | 27,446 | 26,089 | 32,336 | 3 |
| `whitelistSigner` | 2,552 | 2,552 | 2,552 | 2,552 | 1 |

### 与 v1（gas 表）热点对比

| 函数 | v1 Median → v2 Median | v1 Max → v2 Max |
|------|----------------------|-----------------|
| `getPriceInTokenUnits` | 3,444 → **2,976** (−468) | 同左 |
| `list` | 188,781 → **188,193** (−588) | 192,890 → **192,302** (−588) |
| `permitBuy` | 32,786 → **32,535** (−251) | 120,129 → **119,664** (−465) |
| `unlist` | 26,338 → **26,089** (−249) | 32,327 → **32,336** (+9，噪声级) |

**说明**（与 v1 报告相同）: `tokensReceived` 仍只经由 `MyTokenV2.transferWithCallback` 间接调用；下表为该路径上 `transferWithCallback` 的统计。

---

## 3. 相关依赖合约（同次 `gas-report`）

### MyURINFT

- Deployment Cost: 2,289,295；Size: 11,314（与 v1 一致）

### XZXToken

- Deployment Cost: 1,713,194；Size: 10,865（与 v1 一致）

### MyTokenV2

- Deployment Cost: 2,529,767；Size: 13,332（与 v1 一致）

| Function | Min | Avg | Median | Max | # Calls |
|----------|-----|-----|--------|-----|---------|
| `transferWithCallback` | 62,804 | 115,244 | 139,381 | 143,647 | 5 |

v1 同列 Median / Max: 139,913 / 144,648 → v2: **139,381** / **143,647**（随市场回调路径略降）。

---

## 4. 各测试用例 gas（`--gas-report` 下 `[PASS]` 行）

> **注意**: 启用 `--gas-report` 时，Foundry 打印的每测 `gas:` 与**不加**该 flag 时的数值不同（后者通常更低）。本表与 `gas_report_v1.md` 均采用带 `--gas-report` 的口径，便于横向对比。

| 测试 | v2 Gas | v1 Gas（摘自 v1 报告） | 差值 |
|------|--------|-------------------------|------|
| `test_BuyNFT_Reverts` | 318,799 | 319,387 | −588 |
| `test_Invariant_MarketHoldsNoTokens` | 6,140,802 | 6,591,539 | −450,737 |
| `test_List_ByApprovedOperator` | 278,428 | 279,016 | −588 |
| `test_List_RevertWhen_AlreadyListed` | 295,447 | 296,357 | −910 |
| `test_List_RevertWhen_NotOwner` | 54,940 | 55,268 | −328 |
| `test_List_RevertWhen_ZeroNftContract` | 93,830 | 94,158 | −328 |
| `test_List_RevertWhen_ZeroPrice` | 92,286 | 92,614 | −328 |
| `test_List_Success` | 305,931 | 306,987 | −1,056 |
| `test_PermitBuy_RevertWhen_BuyerMismatchInSignature` | 353,665 | 354,582 | −917 |
| `test_PermitBuy_RevertWhen_ExpiredDeadline` | 346,986 | 347,902 | −916 |
| `test_PermitBuy_RevertWhen_InsufficientAmount` | 369,055 | 370,445 | −1,390 |
| `test_PermitBuy_RevertWhen_NotListed` | 104,772 | 105,103 | −331 |
| `test_PermitBuy_RevertWhen_SignerZero` | 3,045,026 | 3,494,632 | −449,606 |
| `test_PermitBuy_RevertWhen_WrongSigner` | 351,373 | 352,290 | −917 |
| `test_PermitBuy_Success` | 454,637 | 455,690 | −1,053 |
| `test_SetWhitelistSigner` | 44,077 | 44,077 | 0 |
| `test_TransferWithCallback_BuySuccess` | 5,757,958 | 6,207,635 | −449,677 |
| `test_TransferWithCallback_RefundExcess` | 5,762,196 | 6,212,225 | −450,029 |
| `test_TransferWithCallback_RevertWhen_InsufficientAmount` | 5,705,240 | 6,154,861 | −449,621 |
| `test_TransferWithCallback_RevertWhen_InvalidDataDecode` | 5,671,954 | 6,121,232 | −449,278 |
| `test_Unlist_RevertWhen_NotListed` | 35,079 | 35,413 | −334 |
| `test_Unlist_RevertWhen_NotLister` | 288,321 | 289,240 | −919 |
| `test_Unlist_Success` | 301,843 | 302,425 | −582 |

含 **`new NFTMarket` + `new MyTokenV2`** 的用例整体约 **少 ~45 万 gas / 测**，与部署 bytecode 变小、每次部署的 calldata/初始化开销下降一致。

---

## 5. 如何复现

```bash
forge test --match-contract NFTMarketV2Test --gas-report
```

不加 gas 报告（本仓库当前优化下 `test_List_Success` 示例）:

```bash
forge test --match-contract NFTMarketV2Test --mt test_List_Success
# [PASS] test_List_Success() (gas: 222647)
```
