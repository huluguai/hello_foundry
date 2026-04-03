# TokenVesting 说明文档

## 解决什么问题

在代币分配、团队激励、投资人解锁等场景中，常见需求是：**不能把代币一次性全部交给受益人**，而要约定「先锁一段时间（cliff），再在一段时间内逐步解锁（线性归属）」。若仅靠口头或链下约定，容易出现提前抛售、信任纠纷等问题。

`TokenVesting` 在链上固化这套规则：代币先进入本合约，按时间自动计算「已归属」额度，受益人（或任何人代其）调用 `release()` 时，才把**当前已归属且尚未转出**的部分转到固定受益人地址。这样释放节奏可审计、不可单方面篡改（部署参数不可变）。

## 核心机制（时间轴）

- **`start`**：时间轴起点，一般为部署区块的 `block.timestamp`。
- **`cliffDuration`**：从 `start` 起算的锁定期（秒）。在 `start + cliffDuration` **之前**，已归属数量为 **0**；在 **恰好** cliff 结束时刻，线性段刚开始，已归属仍为 **0**（与测试一致：cliff 最后一秒与 cliff 结束瞬间都不可领）。
- **`linearDuration`**：cliff 结束后的线性解锁时长（秒）。在此区间内，已归属额度从 0 **线性增长**到「总配额」；到达 `vestingEnd()` 后，100% 归属。

时间关系：

- `cliffEnd() = start + cliffDuration`
- `vestingEnd() = cliffEnd() + linearDuration`

链上只用**秒**表示时长；若业务上按「月」理解，需在部署或脚本里自行换算（例如 `12 * 30 days`），合约不做日历月对齐。

## 「总配额」如何计算（与 OpenZeppelin VestingWallet 一致）

已归属比例始终针对**当前总分配额**计算：

**总分配 = 合约当前 ERC20 余额 + 已累计释放给受益人的数量**

含义：

1. 部署后向本合约 `transfer` 的代币，会按同一条归属曲线参与计算。
2. 若之后在 cliff/线性期间**再次转入**代币，这些新增代币也会按**剩余线性时间**等规则参与同一公式下的分配（曲线形状不变，但总池变大）。

使用前需明确：多笔转入会改变「每人每时刻」的数学含义，通常团队会**一次性转入约定总量**以避免歧义。

## 使用方式（推荐流程）

### 1. 部署

构造参数：

| 参数 | 含义 |
|------|------|
| `beneficiary_` | 接收已释放代币的地址，**不可更改** |
| `token_` | 被锁仓的 ERC20 合约地址 |
| `startTimestamp` | 归属起点 Unix 秒；与部署同块时常用 `uint64(block.timestamp)` |
| `cliffDurationSeconds` | cliff 长度（秒），须 **> 0** |
| `linearDurationSeconds` | 线性段长度（秒），须 **> 0** |

约束：`beneficiary_` 与 `token_` 不能为零地址；`cliff` 与 `linear` 均不能为 0（否则会 `revert`）。

项目内可用 Forge 脚本部署，环境变量说明见 `script/DeployTokenVesting.s.sol` 顶部注释（`VESTING_BENEFICIARY`、`VESTING_TOKEN`、可选 `VESTING_CLIFF_SECONDS` / `VESTING_LINEAR_SECONDS` 等）。

### 2. 注资

部署方或金库对 **Vesting 合约地址** 执行 ERC20 `transfer`，转入约定锁仓总量（需先对该代币 `approve` 若经路由合约转账等，视你的流程而定）。

### 3. 查询与领取

- **`releasable()`**：当前时刻可领取但仍留在合约中的数量。
- **`vestedAmount(timestamp)`**：在任意过去/未来时间戳下，按当前总分配计算的已归属量（只读）。
- **`release()`**：把 `releasable()` 对应数量转给 `beneficiary`，并更新内部已释放累计值；可多次调用，无需固定周期。

任意地址都可调用 `release()`，代币只会转给固定的 `beneficiary`，常用于由项目方代付 gas 帮受益人触发。

### 4. 事件与集成

释放成功会触发 `ERC20Released(token, amount)`，便于索引器或前端展示累计释放。

## 主要对外接口摘要

| 函数/属性 | 说明 |
|-----------|------|
| `beneficiary` | 受益人（immutable） |
| `token` | ERC20（immutable） |
| `start` / `cliffDuration` / `linearDuration` | 时间参数（immutable） |
| `released()` | 已累计转给受益人的代币数量 |
| `cliffEnd()` / `vestingEnd()` | 关键时间节点 |
| `releasable()` | 当前可 `release` 的数量 |
| `release()` | 转出可释放部分（带 `nonReentrant`） |

## 安全与产品注意点

- **受益人与代币不可升级、不可修改**：部署前务必核对地址与代币合约。
- **使用标准 ERC20**；合约通过 OpenZeppelin `SafeERC20` 转账，对非标准返回值更稳妥。
- **cliff 结束瞬间可领仍为 0**：线性段从 cliff 结束之后才开始累积；若产品文案写「12 个月后可领」，需与业务对齐是「第 12 个月末之后按线性」还是「第 12 个月起一次性」，避免用户误解。
- **Reentrancy**：`release()` 使用 `nonReentrant`，与常见 ERC20 组合使用更安全。

## 相关文件

- 合约：`TokenVesting.sol`
- 测试：`test/TokenVesting.t.sol`（含 cliff 边界与分次 `release` 示例）
- 部署脚本：`script/DeployTokenVesting.s.sol`
