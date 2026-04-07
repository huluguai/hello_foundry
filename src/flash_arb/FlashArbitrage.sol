// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Uniswap V2 Pair 在带 data 的 `swap` 末尾会回调；`to` 须为合约。
interface IUniswapV2Callee {
    /// @notice Pair 转出 token 后调用；须在回调内完成还款逻辑。
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

interface IUniswapV2FactoryMin {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairMin {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

/// @dev Router 子集：PoolB 上 A→B 兑换，以及用 factoryA 报价「还 B 换 A」所需输入量。
interface IUniswapV2Router02Min {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
}

/// @title FlashArbitrage
/// @notice 在 `factoryA` 的 PoolA（pairA）闪电借出 `tokenA`，经 `routerB` 在另一工厂的 PoolB 换成 `tokenB`，再将 B 还给 PoolA；盈余 B 转给发起 `executeFlash` 的地址。
/// @dev 仅允许 `factoryA.getPair(t0,t1) == msg.sender` 的 Pair 触发回调，防止恶意 Pair 钓鱼。
/// @dev 调用时序图与调用关系图（Mermaid）：见仓库根目录下 `docs/FlashArbitrage-callflow.md`。
contract FlashArbitrage is IUniswapV2Callee {
    using SafeERC20 for IERC20;

    /// @notice 闪电侧工厂：必须与 `pairA` 一致。
    address public immutable factoryA;
    /// @notice 闪电借出的资产（必须与 pair 中某一侧一致）。
    address public immutable tokenA;
    /// @notice 另一枚代币；在 PoolB 用 A 换 B，用 B 归还 PoolA。
    address public immutable tokenB;

    event FlashStarted(address indexed pairA, uint256 borrowA, address indexed initiator);
    event FlashRepaid(address indexed pairA, uint256 paidB, uint256 bSurplus);

    error NotFromFactoryPair();
    error MustBorrowTokenA();
    error InvalidSides();

    constructor(address factoryA_, address tokenA_, address tokenB_) {
        require(tokenA_ != tokenB_, "identical tokens");
        factoryA = factoryA_;
        tokenA = tokenA_;
        tokenB = tokenB_;
    }

    /// @notice 发起闪电兑换：对 PoolA 调用 `swap`，本合约在回调中完成跨池套利并还款。
    /// @param pairA `factoryA` 上 (tokenA, tokenB) 的 Pair 地址。
    /// @param borrowAmount 从 PoolA 借出的 `tokenA` 数量（wei）。
    /// @param routerB 绑定另一套 Factory（PoolB）的 Router，用于 A→B。
    /// @param routerA 绑定 `factoryA` 的 Router，仅用于 `getAmountsIn` 计算应还 B。
    /// @param minTokenBOut PoolB 路径上 A→B 的最少接受量（滑点保护）。
    /// @param deadline Router 交易的截止时间（unix 秒）。
    function executeFlash(address pairA, uint256 borrowAmount, address routerB, address routerA, uint256 minTokenBOut, uint256 deadline)
        external
    {
        address t0 = IUniswapV2PairMin(pairA).token0();
        address t1 = IUniswapV2PairMin(pairA).token1();
        // 确保 pairA 属于本合约记录的 factoryA，且为正规 Pair
        if (IUniswapV2FactoryMin(factoryA).getPair(t0, t1) != pairA) revert NotFromFactoryPair();

        // V2 闪电单侧出库：tokenA 可能是 token0 或 token1
        uint256 amount0Out;
        uint256 amount1Out;
        if (tokenA == t0) {
            amount0Out = borrowAmount;
        } else if (tokenA == t1) {
            amount1Out = borrowAmount;
        } else {
            revert MustBorrowTokenA();
        }

        // initiator：盈余 B 的接收方；其余参数供回调内 Router 使用
        bytes memory data = abi.encode(msg.sender, routerB, routerA, minTokenBOut, deadline);
        emit FlashStarted(pairA, borrowAmount, msg.sender);
        IUniswapV2PairMin(pairA).swap(amount0Out, amount1Out, address(this), data);
    }

    /// @inheritdoc IUniswapV2Callee
    /// @dev `msg.sender` 为 PoolA Pair；Pair 已把借出的 tokenA 转入本合约。
    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        address t0 = IUniswapV2PairMin(msg.sender).token0();
        address t1 = IUniswapV2PairMin(msg.sender).token1();
        if (IUniswapV2FactoryMin(factoryA).getPair(t0, t1) != msg.sender) revert NotFromFactoryPair();
        // 闪电只允许一侧输出：amount0 与 amount1 恰有一侧 > 0
        if ((amount0 > 0) == (amount1 > 0)) revert InvalidSides();

        (address initiator, address routerB, address routerA, uint256 minTokenBOut, uint256 deadline) =
            abi.decode(data, (address, address, address, uint256, uint256));

        uint256 borrowedA = amount0 > 0 ? amount0 : amount1;
        address borrowedAddr = amount0 > 0 ? t0 : t1;
        if (borrowedAddr != tokenA) revert MustBorrowTokenA();

        IERC20(tokenA).safeIncreaseAllowance(routerB, borrowedA);

        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;

        // 在 PoolB（routerB 所属工厂）用全部借来的 A 换 B
        IUniswapV2Router02Min(routerB).swapExactTokensForTokens(borrowedA, minTokenBOut, path, address(this), deadline);

        // pathRepay：要得到 borrowedA 个 tokenA，需要输入多少 tokenB（与 PoolA 恒积公式一致）
        address[] memory pathRepay = new address[](2);
        pathRepay[0] = tokenB;
        pathRepay[1] = tokenA;

        uint256[] memory amountsIn = IUniswapV2Router02Min(routerA).getAmountsIn(borrowedA, pathRepay);
        uint256 repayB = amountsIn[0];

        uint256 balB = IERC20(tokenB).balanceOf(address(this));
        require(balB >= repayB, "insufficient B to repay");

        // 还给发起闪电的 Pair（msg.sender），否则 swap 末尾 k 校验失败
        IERC20(tokenB).safeTransfer(msg.sender, repayB);

        uint256 surplus = balB - repayB;
        emit FlashRepaid(msg.sender, repayB, surplus);

        if (surplus > 0 && initiator != address(0)) {
            IERC20(tokenB).safeTransfer(initiator, surplus);
        }
    }
}
