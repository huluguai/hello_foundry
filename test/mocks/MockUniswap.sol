// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "../../src/v2/meme/interfaces/IUniswapV2.sol";

contract MockLpToken is ERC20 {
    constructor() ERC20("MockLP", "mLP") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Fixed non-zero reserves for `buyMeme` reserve checks
contract MockPair is IUniswapV2Pair {
    address public immutable token0_;
    address public immutable token1_;

    constructor(address tokenA, address tokenB) {
        (token0_, token1_) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function token0() external view returns (address) {
        return token0_;
    }

    function getReserves() external pure returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        reserve0 = uint112(1e18);
        reserve1 = uint112(1e18);
        blockTimestampLast = 0;
    }
}

contract MockUniswapFactory is IUniswapV2Factory {
    address public pair;

    function setPair(address p) external {
        pair = p;
    }

    function getPair(address, address) external view returns (address) {
        return pair;
    }
}

/**
 * @dev Records addLiquidityETH params; mints LP to `to`. `swapExactETHForTokens` pulls pre-funded meme balance.
 */
contract MockUniswapV2Router is IUniswapV2Router02 {
    MockUniswapFactory public immutable uniFactory;
    address public immutable weth;
    MockLpToken public immutable lpToken;

    uint256 public mockAmountOut;

    uint256 public lastAddLiquidityEth;
    address public lastAddLiquidityTo;
    uint256 public lastTokenDesired;

    constructor(address weth_, MockUniswapFactory factory_) {
        weth = weth_;
        uniFactory = factory_;
        lpToken = new MockLpToken();
    }

    function factory() external view returns (address) {
        return address(uniFactory);
    }

    function WETH() external view returns (address) {
        return weth;
    }

    function setMockAmountOut(uint256 v) external {
        mockAmountOut = v;
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
        lastAddLiquidityEth = msg.value;
        lastAddLiquidityTo = to;
        lastTokenDesired = amountTokenDesired;
        liquidity = 1e18;
        lpToken.mint(to, liquidity);
        return (amountTokenDesired, msg.value, liquidity);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata)
        external
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = mockAmountOut;
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external payable returns (uint256[] memory amounts) {
        require(mockAmountOut >= amountOutMin, "MockRouter: slippage");
        IERC20 token = IERC20(path[1]);
        token.transfer(to, mockAmountOut);
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = mockAmountOut;
    }
}
