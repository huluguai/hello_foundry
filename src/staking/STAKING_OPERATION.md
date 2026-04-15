# Staking 合约操作文档

## 1. 目录与合约职责

- `KKToken.sol`：奖励代币，只有绑定的 `StakingPool` 可以 `mint`。
- `StakingPool.sol`：核心质押池，接收 `WETH`，存入 `ERC4626 Vault`，按区块给用户发放 `KK`。
- `interfaces/IWETH.sol`：最小 `WETH` 接口（`deposit/withdraw`）。
- `mocks/MockWETH.sol`：本地测试用 `WETH`，`ETH <-> WETH` 1:1 包装/解包。
- `mocks/MockERC4626Vault.sol`：本地测试用金库，底层资产为 `WETH`，share 为 `mvSHARE`。

---

## 2. 核心机制说明

`StakingPool` 采用 MasterChef 风格奖励模型：

- 全局累计值：`accRewardPerShare`（每 1 share 累计 KK，按 `1e12` 放大）。
- 更新时间点：`lastRewardBlock`。
- 用户状态：
  - `shares`：用户持有的 vault share（质押权重）。
  - `rewardDebt`：用户已结算奖励债务。
- 待领取奖励公式：
  - `pending = shares * accRewardPerShare / PRECISION - rewardDebt`

执行 `deposit/withdraw/claim` 时，都会先：

1. `_updatePool()`：把区块增量奖励累计进全局；
2. `_harvest(user)`：把用户截至当前的 pending KK 铸造到用户地址；
3. 再处理份额变化（如有）并刷新 `rewardDebt`。

---

## 3. 部署与初始化流程

建议顺序：

1. 部署 `WETH`（测试环境可用 `MockWETH`）。
2. 部署 `ERC4626 Vault`（资产必须是 `WETH`，测试环境可用 `MockERC4626Vault`）。
3. 部署 `KKToken(initialOwner)`。
4. 部署 `StakingPool(weth, vault, kk, rewardPerBlock)`。
5. 调用 `KKToken.setStakingPool(pool)`（只能设置一次）。

关键校验：

- `StakingPool` 构造函数会检查 `vault.asset() == weth`。
- `rewardPerBlock` 必须大于 0。
- `KKToken` 仅允许已绑定池子地址调用 `mint`。

---

## 4. 常见操作手册

### 4.1 质押（用户持有 WETH）

1. 用户先对 `StakingPool` 执行 `WETH.approve(pool, amount)`。
2. 调用 `StakingPool.deposit(amount)`。
3. 池子把 WETH 存入 Vault，获得 share 并记到用户 `shares`。

### 4.2 质押（用户持有 ETH）

1. 直接调用 `StakingPool.depositETH{value: amount}()`。
2. 池子内部先 `weth.deposit()` 把 ETH 包装成 WETH。
3. 再把 WETH 存入 Vault，按返回 share 入账。

### 4.3 领取奖励

1. 调用 `StakingPool.claim()`。
2. 池子更新奖励并执行 `_harvest`。
3. 由 `KKToken.mint(user, pending)` 向用户发放 KK。

### 4.4 赎回

1. 调用 `StakingPool.withdraw(shares)`。
2. 池子先结算并发放 KK。
3. 从 Vault 按 share 赎回 WETH，直接转给用户。

---

## 5. 调用时序图

### 5.1 `depositETH()` 调用时序

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant P as StakingPool
    participant W as WETH
    participant V as ERC4626 Vault
    participant K as KKToken

    U->>P: depositETH{value: ETH}()
    P->>P: _updatePool()
    P->>P: _harvest(U)
    alt pending > 0
        P->>K: mint(U, pendingKK)
        K-->>U: KK
    end
    P->>W: deposit{value: ETH}()
    W-->>P: WETH
    P->>V: deposit(WETH, receiver=P)
    V-->>P: vaultShares
    P->>P: user.shares += vaultShares
    P->>P: user.rewardDebt = shares*acc/PRECISION
    P-->>U: Deposit event
```

### 5.2 `withdraw(shares)` 调用时序

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant P as StakingPool
    participant V as ERC4626 Vault
    participant K as KKToken

    U->>P: withdraw(shares)
    P->>P: _updatePool()
    P->>P: _harvest(U)
    alt pending > 0
        P->>K: mint(U, pendingKK)
        K-->>U: KK
    end
    P->>P: user.shares -= shares
    P->>V: redeem(shares, receiver=U, owner=P)
    V-->>U: WETH assetsOut
    P->>P: user.rewardDebt = shares*acc/PRECISION
    P-->>U: Withdraw event
```

---

## 6. Token 转换关系图

```mermaid
flowchart LR
    ETH[ETH]
    WETH[WETH]
    SHARE[Vault Share\nmvSHARE]
    KK[KK Token]
    U[User]
    P[StakingPool]
    V[ERC4626 Vault]

    U -- depositETH --> P
    P -- wrap --> WETH
    U -- deposit(WETH) --> P
    P -- deposit asset --> V
    V -- mint share --> P
    P -- accounting shares --> U

    P -- redeem share --> V
    V -- return WETH --> U

    P -- mint reward --> KK
    KK -- transfer minted KK --> U
```

关系说明：

- 资产主线：`ETH -> WETH -> Vault Share`（入池）与 `Vault Share -> WETH`（出池）。
- 激励主线：用户依据持有 `Vault Share` 权重，按区块获得 `KK`。
- `StakingPool` 只持有 Vault Share；用户在池内通过记账映射持有对应份额权益。

---

## 7. 运行与运维注意事项

- 无人质押期间（`totalShares == 0`）的区块奖励不会分配给任何人；仅推进 `lastRewardBlock`。
- `KKToken.setStakingPool` 只能执行一次，部署脚本要严格保证顺序。
- `deposit` 使用 `safeIncreaseAllowance`，长期运行可关注授权增长策略（若未来接入不同 vault，可考虑重置授权策略）。
- 奖励发放为“按块线性、按 share 比例”；Vault 收益（share 对 asset 的兑换率变化）与 KK 挖矿是两条独立收益线。
- 本实现 `withdraw` 赎回的是 `WETH`；若产品层面希望用户拿回 `ETH`，需在外层再加一次 `WETH.withdraw` 封装逻辑。
