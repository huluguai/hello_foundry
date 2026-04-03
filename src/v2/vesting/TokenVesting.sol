// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TokenVesting
 * @notice 单币种 ERC20 锁仓：先经过 cliff，之后在固定时长内线性归属；已归属部分通过 `release()` 转给受益人。
 * @dev
 * - 总配额为「合约当前余额 + 已累计释放」，与 OpenZeppelin `VestingWallet` 一致；部署后向本合约转入代币即可。
 * - 归属曲线：在 `[start, start + cliffDuration)` 内为 0；在 `[start + cliffDuration, start + cliffDuration + linearDuration)` 内线性增加；
 *   达到 `start + cliffDuration + linearDuration` 后 100% 可归属。
 * - “月”由部署时传入的秒数表达（例如脚本中使用 `12 * 30 days` 与 `24 * 30 days`），链上不做日历换算。
 */
contract TokenVesting is ReentrancyGuard {
    using SafeERC20 for IERC20;

    event ERC20Released(address indexed token, uint256 amount);

    /// @notice 接收已释放代币的地址（固定，不可转让）。
    address public immutable beneficiary;
    /// @notice 被锁仓的 ERC20。
    IERC20 public immutable token;
    /// @notice 归属时间轴起点（通常为部署时刻的 `block.timestamp`）。
    uint64 public immutable start;
    /// @notice Cliff 时长（秒），此区间内已归属数量为 0。
    uint64 public immutable cliffDuration;
    /// @notice Cliff 结束后线性解锁的时长（秒）。
    uint64 public immutable linearDuration;

    uint256 private _released;

    error ZeroAddress();
    error ZeroDuration();

    /**
     * @param beneficiary_ 受益人
     * @param token_ 锁定的 ERC20
     * @param startTimestamp 时间轴起点（与部署同区块时传入 `uint64(block.timestamp)`）
     * @param cliffDurationSeconds cliff 长度（秒）
     * @param linearDurationSeconds cliff 结束后线性段长度（秒）
     */
    constructor(
        address beneficiary_,
        address token_,
        uint64 startTimestamp,
        uint64 cliffDurationSeconds,
        uint64 linearDurationSeconds
    ) {
        if (beneficiary_ == address(0) || token_ == address(0)) revert ZeroAddress();
        if (cliffDurationSeconds == 0 || linearDurationSeconds == 0) revert ZeroDuration();

        beneficiary = beneficiary_;
        token = IERC20(token_);
        start = startTimestamp;
        cliffDuration = cliffDurationSeconds;
        linearDuration = linearDurationSeconds;
    }

    /// @notice 已释放给受益人的累计数额（与 OpenZeppelin VestingWallet 中 `released(token)` 含义一致）。
    function released() external view returns (uint256) {
        return _released;
    }

    /// @notice Cliff 结束时刻（`start + cliffDuration`）。
    function cliffEnd() public view returns (uint256) {
        return uint256(start) + uint256(cliffDuration);
    }

    /// @notice 全部可归属时刻（线性段结束）。
    function vestingEnd() public view returns (uint256) {
        return cliffEnd() + uint256(linearDuration);
    }

    /**
     * @notice 在指定时间戳下已归属的代币数量（基于当前 `totalAllocation`）。
     * @param timestamp 链上时间秒
     */
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        return _vestingSchedule(_totalAllocation(), timestamp);
    }

    /// @notice 当前时刻可领取但仍在本合约中的代币数量。
    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - _released;
    }

    /// @notice 将当前已归属且尚未转出的代币转给 `beneficiary`。
    function release() external nonReentrant {
        uint256 amount = releasable();
        _released += amount;
        emit ERC20Released(address(token), amount);
        token.safeTransfer(beneficiary, amount);
    }

    /// @dev 总分配 = 当前余额 + 已释放（与 OZ VestingWallet 一致，后续转入的代币也会按同一曲线归属）。
    function _totalAllocation() private view returns (uint256) {
        return token.balanceOf(address(this)) + _released;
    }

    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp) private view returns (uint256) {
        uint256 cliffEnd_ = cliffEnd();
        if (timestamp < cliffEnd_) {
            return 0;
        }
        uint256 end_ = vestingEnd();
        if (timestamp >= end_) {
            return totalAllocation;
        }
        return (totalAllocation * (uint256(timestamp) - cliffEnd_)) / uint256(linearDuration);
    }
}
