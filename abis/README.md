# 闪电兑换 DApp 用 ABI 导出

本目录为前端 / DApp 准备的 **JSON ABI 数组**（可直接给 viem `parseAbi` / ethers `Interface` / wagmi `abi` 使用）。

## 文件说明

| 文件 | 用途 |
|------|------|
| [FlashArbitrage.json](./FlashArbitrage.json) | 套利合约：读 `factoryA` / `tokenA` / `tokenB`，写 `executeFlash`；监听 `FlashStarted` / `FlashRepaid`。**不要**在 DApp 中调用 `uniswapV2Call`（仅 Pair 在闪电流程中回调）。 |
| [UniswapV2Router02.min.json](./UniswapV2Router02.min.json) | Router 精简：`getAmountsOut` / `getAmountsIn`（估算 `minTokenBOut`）、`factory` / `WETH`（校验或调试）。 |
| [UniswapV2Factory.min.json](./UniswapV2Factory.min.json) | Factory 精简：`getPair`（解析 `pairA` / `pairB`）、`createPair`（若前端自己建池）、`allPairsLength`。 |
| [UniswapV2Pair.min.json](./UniswapV2Pair.min.json) | Pair 精简：`token0` / `token1` / `getReserves`（展示价格或确认代币顺序）。 |
| [ERC20.min.json](./ERC20.min.json) | 通用 ERC20：`balanceOf` / `approve` / `allowance` / `decimals` / `symbol` / `name` 等。 |
| [MyToken.json](./MyToken.json) | 与链上一致的 `MyToken` 完整 ABI（继承 ERC20 + 额外事件等）；若只用标准 ERC20，可只用 `ERC20.min.json`。 |

## DApp 调用 `executeFlash` 所需链上参数

1. 读 `FlashArbitrage.tokenA()`、`tokenB()`、`factoryA()`（可选，用于展示）。
2. 用 `UniswapV2Factory.getPair(tokenA, tokenB)`（分别对 factoryA / factoryB）得到 `pairA` 与 `pairB` 地址。
3. `routerA`、`routerB`：部署脚本日志中的两个 Router 地址（或写入配置）。
4. `borrowAmount`：用户输入（wei）。
5. `minTokenBOut`：对 **routerB** 调用 `getAmountsOut(borrowAmount, [tokenA, tokenB])`，取返回数组最后一项再乘以滑点系数（如 90%）。
6. `deadline`：`Math.floor(Date.now() / 1000) + 600` 等。

**注意**：用户 **无需** 对 `FlashArbitrage` 预先 `approve` TokenA；合约在回调内自行 `approve` RouterB。仅需保证两池流动性与价差足够，否则交易会 `revert`。

## 重新生成（合约变更后）

在项目根目录执行：

```bash
forge build
python3 -c "
import json, pathlib
root = pathlib.Path('.')
json.dump(json.load(open('out/FlashArbitrage.sol/FlashArbitrage.json'))['abi'], open('abis/FlashArbitrage.json','w'), indent=2)
json.dump(json.load(open('out/MyToken.sol/MyToken.json'))['abi'], open('abis/MyToken.json','w'), indent=2)
print('ok')
"
# Router / Factory 精简片段若需更新，可从 lib/uniswap-artifacts/*.json 再筛一次（见仓库中历史提交或自行用 jq）。
```

`UniswapV2Router02.min.json` / `UniswapV2Factory.min.json` 若官方 artifact 升级，可从 `lib/uniswap-artifacts/` 重新筛选函数项。
