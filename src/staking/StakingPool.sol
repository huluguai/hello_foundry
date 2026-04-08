// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IWETH} from "./interfaces/IWETH.sol";
import {KKToken} from "./KKToken.sol";

/// @title StakingPool
/// @notice 将 WETH 存入 ERC4626 金库赚取利息；按金库份额权重、每块固定释放 KK（MasterChef 式 accRewardPerShare + rewardDebt）。
contract StakingPool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev 与 SushiSwap MasterChef 一致，放大累加精度，减少除法截断误差。
    uint256 public constant PRECISION = 1e12;

    IWETH public immutable weth;
    IERC4626 public immutable vault;
    KKToken public immutable kk;

    /// @notice 每个新区块向本池释放的 KK 数量（wei，通常 18 位小数）。
    uint256 public immutable rewardPerBlock;

    /// @notice 每 1 wei 金库份额累计应得的 KK（已乘 PRECISION）。
    uint256 public accRewardPerShare;
    /// @notice 上次更新奖励会计的区块号。
    uint256 public lastRewardBlock;

    /// @notice 池内登记的总份额（与合约持有的 vault 份额一致，除非舍入误差）。
    uint256 public totalShares;

    struct UserInfo {
        /// @notice 用户在本池的金库份额数量（质押权重）。
        uint256 shares;
        /// @notice 已清算到「accRewardPerShare」基准的债务，用于计算待领取：`shares * acc / PRECISION - rewardDebt`。
        uint256 rewardDebt;
    }

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 assets, uint256 sharesMinted);
    event Withdraw(address indexed user, uint256 sharesBurned, uint256 assetsOut);
    event Claim(address indexed user, uint256 amount);

    constructor(IWETH weth_, IERC4626 vault_, KKToken kk_, uint256 rewardPerBlock_) {
        require(address(weth_) != address(0) && address(vault_) != address(0) && address(kk_) != address(0), "StakingPool: zero address");
        require(rewardPerBlock_ > 0, "StakingPool: rewardPerBlock");
        require(vault_.asset() == address(weth_), "StakingPool: vault asset mismatch");

        weth = weth_;
        vault = vault_;
        kk = kk_;
        rewardPerBlock = rewardPerBlock_;

        lastRewardBlock = block.number;
    }

    // -------------------------------------------------------------------------
    // 视图
    // -------------------------------------------------------------------------

    /// @notice 按当前链上状态（含未写入的区块区间）估算用户待领取 KK。
    function pendingReward(address user) external view returns (uint256) {
        uint256 acc = accRewardPerShare;
        uint256 supply = totalShares;
        uint256 last = lastRewardBlock;

        // 步骤：与 updatePool 相同逻辑，仅内存中计算最新 acc，不写状态。
        if (block.number > last && supply > 0) {
            uint256 blocks = block.number - last;
            uint256 reward = blocks * rewardPerBlock;
            acc += (reward * PRECISION) / supply;
        }

        UserInfo storage u = userInfo[user];
        return (u.shares * acc) / PRECISION - u.rewardDebt;
    }

    // -------------------------------------------------------------------------
    // 外部：质押 / 提款 / 领奖励
    // -------------------------------------------------------------------------

    /// @notice 使用 WETH 质押；WETH 转入本合约后存入 `vault`，按实际获得的份额记账。
    function deposit(uint256 assets) external nonReentrant {
        require(assets > 0, "StakingPool: zero assets");
        // 步骤 1：把全局奖励累计到当前区块（更新 accRewardPerShare、lastRewardBlock）。
        _updatePool();
        // 步骤 2：按更新后的 acc 结算该用户已有份额的 KK，并 mint。
        _harvest(msg.sender);

        // 步骤 3：拉取 WETH 并授权金库，将资产存入 ERC4626；以返回的份额作为质押权重。
        IERC20(address(weth)).safeTransferFrom(msg.sender, address(this), assets);
        IERC20(address(weth)).safeIncreaseAllowance(address(vault), assets);
        uint256 sharesOut = vault.deposit(assets, address(this));

        // 步骤 4：增加用户份额与总份额，并按新份额重置 rewardDebt（已领部分从 debt 中体现）。
        UserInfo storage user = userInfo[msg.sender];
        user.shares += sharesOut;
        totalShares += sharesOut;
        user.rewardDebt = (user.shares * accRewardPerShare) / PRECISION;

        emit Deposit(msg.sender, assets, sharesOut);
    }

    /// @notice 使用原生 ETH：先 wrap 为 WETH，再与 `deposit` 相同逻辑。
    function depositETH() external payable nonReentrant {
        require(msg.value > 0, "StakingPool: zero eth");
        // 步骤 1：全局奖励累计。
        _updatePool();
        // 步骤 2：结算该用户已有份额的 KK。
        _harvest(msg.sender);

        // 步骤 3：ETH → WETH（余额在本合约）。
        weth.deposit{value: msg.value}();

        uint256 assets = msg.value;
        IERC20(address(weth)).safeIncreaseAllowance(address(vault), assets);
        uint256 sharesOut = vault.deposit(assets, address(this));

        // 步骤 4：更新份额与 rewardDebt。
        UserInfo storage user = userInfo[msg.sender];
        user.shares += sharesOut;
        totalShares += sharesOut;
        user.rewardDebt = (user.shares * accRewardPerShare) / PRECISION;

        emit Deposit(msg.sender, assets, sharesOut);
    }

    /// @notice 按金库份额赎回；份额从池子持有部分扣减，WETH 直接转给用户。
    function withdraw(uint256 shares) external nonReentrant {
        require(shares > 0, "StakingPool: zero shares");
        UserInfo storage user = userInfo[msg.sender];
        require(user.shares >= shares, "StakingPool: insufficient shares");

        // 步骤 1：更新全局 acc。
        _updatePool();
        // 步骤 2：先领取 KK 到当前份额。
        _harvest(msg.sender);

        // 步骤 3：减少记账份额，并向用户赎回底层资产。
        user.shares -= shares;
        totalShares -= shares;
        uint256 assetsOut = vault.redeem(shares, msg.sender, address(this));

        // 步骤 4：按剩余份额重置 rewardDebt。
        user.rewardDebt = (user.shares * accRewardPerShare) / PRECISION;

        emit Withdraw(msg.sender, shares, assetsOut);
    }

    /// @notice 仅领取 KK，不改动质押份额。
    function claim() external nonReentrant {
        // 步骤 1：更新全局 acc。
        _updatePool();
        // 步骤 2：计算 pending 并 mint KK，刷新 rewardDebt。
        _harvest(msg.sender);
    }

    // -------------------------------------------------------------------------
    // 内部
    // -------------------------------------------------------------------------

    /// @dev MasterChef 式池更新：把 `[lastRewardBlock, block.number)` 区间内应发的 KK 总量，按 `totalShares` 均摊进 `accRewardPerShare`。
    /// @dev 公式：`accRewardPerShare += (blockDelta * rewardPerBlock * PRECISION) / totalShares`。
    function _updatePool() internal {
        // 步骤 A：同块内重复调用不重复累计。
        if (block.number <= lastRewardBlock) {
            return;
        }

        if (totalShares == 0) {
            // 步骤 B：无人质押时与 MasterChef 一致——不增加 acc，仅把 `lastRewardBlock` 追到当前块（该区间排放无人获得）。
            lastRewardBlock = block.number;
            return;
        }

        // 步骤 C：有份额时，按块数线性释放并累加到「每份额累计奖励」。
        uint256 blocks = block.number - lastRewardBlock;
        uint256 reward = blocks * rewardPerBlock;
        accRewardPerShare += (reward * PRECISION) / totalShares;
        lastRewardBlock = block.number;
    }

    /// @dev 待领取 = `shares * accRewardPerShare / PRECISION - rewardDebt`；`mint` 后将 `rewardDebt` 更新为 `shares * acc / PRECISION`，表示已清算到当前累计点。
    function _harvest(address user) internal {
        UserInfo storage u = userInfo[user];
        uint256 pending = (u.shares * accRewardPerShare) / PRECISION - u.rewardDebt;
        if (pending > 0) {
            kk.mint(user, pending);
            emit Claim(user, pending);
        }
        u.rewardDebt = (u.shares * accRewardPerShare) / PRECISION;
    }
}
