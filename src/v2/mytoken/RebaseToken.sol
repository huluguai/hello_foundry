// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RebaseToken
/// @notice 教学用途的 rebase 通缩代币：每满一年在上一年基础上通缩 1%。
contract RebaseToken is IERC20 {
    string public constant name = "Rebase Deflation Token";
    string public constant symbol = "RDT";
    uint8 public constant decimals = 18;

    uint256 public constant SCALE = 1e18;
    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 1e18;
    uint256 public constant ANNUAL_RATIO = 99e16; // 0.99 * 1e18
    uint256 public constant YEAR = 365 days;

    // raw 份额余额：用户真实显示余额 = raw * scalingFactor / SCALE
    mapping(address => uint256) private _rawBalances;
    mapping(address => mapping(address => uint256)) private _allowances;
    // raw 总份额在本示例中不变，rebase 仅调整全局缩放因子
    uint256 private _rawTotalSupply;

    // 全局缩放因子，初始 1e18；每年乘以 0.99
    uint256 public scalingFactor;
    // 上次成功执行 rebase 的时间戳（按整年推进）
    uint256 public lastRebaseTime;

    event Rebased(uint256 yearsElapsed, uint256 newScalingFactor, uint256 newTotalSupply);

    constructor() {
        scalingFactor = SCALE;
        lastRebaseTime = block.timestamp;

        _rawTotalSupply = INITIAL_SUPPLY;
        _rawBalances[msg.sender] = INITIAL_SUPPLY;
        emit Transfer(address(0), msg.sender, INITIAL_SUPPLY);
    }

    function totalSupply() external view override returns (uint256) {
        return _visibleFromRaw(_rawTotalSupply);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _visibleFromRaw(_rawBalances[account]);
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        require(allowed >= value, "RebaseToken: insufficient allowance");

        if (allowed != type(uint256).max) {
            unchecked {
                _allowances[from][msg.sender] = allowed - value;
            }
            emit Approval(from, msg.sender, _allowances[from][msg.sender]);
        }

        _transfer(from, to, value);
        return true;
    }

    function rebase() external returns (uint256 newTotalSupply) {
        // 只按“完整经过的年份”执行通缩，未满一年不生效。
        uint256 yearsElapsed = (block.timestamp - lastRebaseTime) / YEAR;
        if (yearsElapsed == 0) {
            return _visibleFromRaw(_rawTotalSupply);
        }

        // 一次性补齐多年的 rebase：factor = factor * (0.99 ^ yearsElapsed)
        uint256 factor = scalingFactor;
        for (uint256 i = 0; i < yearsElapsed; i++) {
            factor = (factor * ANNUAL_RATIO) / SCALE;
        }

        scalingFactor = factor;
        lastRebaseTime += yearsElapsed * YEAR;

        newTotalSupply = _visibleFromRaw(_rawTotalSupply);
        emit Rebased(yearsElapsed, factor, newTotalSupply);
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "RebaseToken: transfer to zero");

        // 可见金额转 raw 份额时向上取整，避免因截断导致接收方少拿。
        uint256 rawAmount = _rawFromVisibleCeil(value);
        uint256 fromBalance = _rawBalances[from];
        require(fromBalance >= rawAmount, "RebaseToken: insufficient balance");

        unchecked {
            _rawBalances[from] = fromBalance - rawAmount;
        }
        _rawBalances[to] += rawAmount;

        emit Transfer(from, to, value);
    }

    function _visibleFromRaw(uint256 rawAmount) internal view returns (uint256) {
        // 向下取整：与 Solidity 整数除法一致。
        return (rawAmount * scalingFactor) / SCALE;
    }

    function _rawFromVisibleCeil(uint256 visibleAmount) internal view returns (uint256) {
        if (visibleAmount == 0) return 0;
        // 向上取整换算：ceil(visible * SCALE / scalingFactor)
        return ((visibleAmount * SCALE) + scalingFactor - 1) / scalingFactor;
    }
}
