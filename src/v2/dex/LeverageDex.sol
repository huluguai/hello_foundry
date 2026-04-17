// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title LeverageDex
/// @notice A simplified perpetual-like vAMM leverage DEX with one active position per user.
contract LeverageDex {
    uint256 public constant BPS = 10_000;
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant MAX_LEVERAGE = 10;
    uint256 public constant MAINTENANCE_MARGIN_BPS = 500; // 5%
    uint256 public constant LIQUIDATION_REWARD_BPS = 500; // 5%

    uint256 public vBaseReserve;
    uint256 public vQuoteReserve;

    struct Position {
        uint256 margin;
        uint256 notional;
        uint256 size; // base asset amount in 1e18 precision
        bool isLong;
        uint256 entryPriceX18;
        bool isOpen;
    }

    mapping(address => Position) public positions;

    event PositionOpened(
        address indexed user, uint256 margin, uint256 notional, uint256 size, bool isLong, uint256 entryPriceX18
    );
    event PositionClosed(address indexed user, int256 pnl, uint256 settlement, uint256 exitPriceX18);
    event PositionLiquidated(address indexed user, address indexed liquidator, int256 pnl, uint256 userSettlement, uint256 reward);

    error PositionExists();
    error NoOpenPosition();
    error InvalidLeverage();
    error InsufficientMargin();
    error InvalidNotional();
    error NotLiquidatable();
    error InvalidReserve();

    constructor(uint256 _vBaseReserve, uint256 _vQuoteReserve) {
        if (_vBaseReserve == 0 || _vQuoteReserve == 0) revert InvalidReserve();
        vBaseReserve = _vBaseReserve;
        vQuoteReserve = _vQuoteReserve;
    }

    function getMarkPriceX18() public view returns (uint256) {
        return (vQuoteReserve * PRICE_PRECISION) / vBaseReserve;
    }

    function openPosition(uint256 _margin, uint256 level, bool long) external {
        if (positions[msg.sender].isOpen) revert PositionExists();
        if (_margin == 0) revert InsufficientMargin();
        if (level == 0 || level > MAX_LEVERAGE) revert InvalidLeverage();

        uint256 notional = _margin * level;
        if (!long && notional >= vQuoteReserve) revert InvalidNotional();
        uint256 size = _simulateAndApplyTrade(notional, long);
        uint256 entryPriceX18 = (notional * PRICE_PRECISION) / size;

        positions[msg.sender] = Position({
            margin: _margin,
            notional: notional,
            size: size,
            isLong: long,
            entryPriceX18: entryPriceX18,
            isOpen: true
        });

        emit PositionOpened(msg.sender, _margin, notional, size, long, entryPriceX18);
    }

    function closePosition() external returns (uint256 settlement) {
        Position memory pos = positions[msg.sender];
        if (!pos.isOpen) revert NoOpenPosition();

        (int256 pnl, uint256 exitPriceX18) = _closePositionAndComputePnl(msg.sender, pos);
        settlement = _computeSettlement(pos.margin, pnl);

        emit PositionClosed(msg.sender, pnl, settlement, exitPriceX18);
    }

    function liquidatePosition(address _user) external returns (uint256 userSettlement, uint256 reward) {
        Position memory pos = positions[_user];
        if (!pos.isOpen) revert NoOpenPosition();
        if (!_isLiquidatable(pos)) revert NotLiquidatable();

        (int256 pnl, uint256 exitPriceX18) = _closePositionAndComputePnl(_user, pos);
        uint256 remaining = _computeSettlement(pos.margin, pnl);
        reward = (remaining * LIQUIDATION_REWARD_BPS) / BPS;
        userSettlement = remaining - reward;

        emit PositionLiquidated(_user, msg.sender, pnl, userSettlement, reward);
        emit PositionClosed(_user, pnl, userSettlement, exitPriceX18);
    }

    function previewPnl(address user) external view returns (int256 pnl, uint256 markPriceX18, uint256 equity) {
        Position memory pos = positions[user];
        if (!pos.isOpen) return (0, getMarkPriceX18(), 0);

        markPriceX18 = getMarkPriceX18();
        pnl = _calcPnl(pos, markPriceX18);
        equity = _computeSettlement(pos.margin, pnl);
    }

    function marginRatioBps(address user) external view returns (uint256) {
        Position memory pos = positions[user];
        if (!pos.isOpen) revert NoOpenPosition();
        return _marginRatioBps(pos);
    }

    function _closePositionAndComputePnl(address user, Position memory pos) internal returns (int256 pnl, uint256 exitPriceX18) {
        exitPriceX18 = getMarkPriceX18();
        pnl = _calcPnl(pos, exitPriceX18);
        _simulateAndApplyTrade(pos.notional, !pos.isLong);
        delete positions[user];
    }

    function _simulateAndApplyTrade(uint256 quoteAmount, bool isLong) internal returns (uint256 baseDelta) {
        uint256 k = vBaseReserve * vQuoteReserve;
        uint256 nextBase;
        uint256 nextQuote;

        if (isLong) {
            nextQuote = vQuoteReserve + quoteAmount;
            nextBase = k / nextQuote;
            baseDelta = vBaseReserve - nextBase;
        } else {
            nextQuote = vQuoteReserve - quoteAmount;
            nextBase = k / nextQuote;
            baseDelta = nextBase - vBaseReserve;
        }

        vBaseReserve = nextBase;
        vQuoteReserve = nextQuote;
    }

    function _calcPnl(Position memory pos, uint256 priceX18) internal pure returns (int256 pnl) {
        if (pos.isLong) {
            pnl = int256((pos.size * priceX18) / PRICE_PRECISION) - int256(pos.notional);
        } else {
            pnl = int256(pos.notional) - int256((pos.size * priceX18) / PRICE_PRECISION);
        }
    }

    function _computeSettlement(uint256 margin, int256 pnl) internal pure returns (uint256) {
        int256 equity = int256(margin) + pnl;
        if (equity <= 0) return 0;
        return uint256(equity);
    }

    function _isLiquidatable(Position memory pos) internal view returns (bool) {
        uint256 ratio = _marginRatioBps(pos);
        return ratio <= MAINTENANCE_MARGIN_BPS;
    }

    function _marginRatioBps(Position memory pos) internal view returns (uint256) {
        int256 pnl = _calcPnl(pos, getMarkPriceX18());
        uint256 equity = _computeSettlement(pos.margin, pnl);
        return (equity * BPS) / pos.notional;
    }
}
