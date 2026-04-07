// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MyToken} from "../src/flash_arb/MyToken.sol";
import {FlashArbitrage} from "../src/flash_arb/FlashArbitrage.sol";
import {UniswapArtifactLib} from "../src/flash_arb/UniswapArtifactLib.sol";

interface IUniFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint256[] memory amounts);
}

contract FlashArbitrageTest is Test {
    uint256 internal constant SUPPLY = 10_000_000 * 1e18;
    uint256 internal constant BORROW_A = 500 * 1e18;

    function test_flash_swap_cross_pool_arbitrage_repays_and_profits() public {
        _runFlash();
    }

    function _runFlash() internal {
        address deployer = address(this);

        address weth = UniswapArtifactLib.deployFromArtifact(vm, "WETH9.json", bytes(""));
        address factoryA = UniswapArtifactLib.deployFromArtifact(vm, "UniswapV2Factory.json", abi.encode(deployer));
        address factoryB = UniswapArtifactLib.deployFromArtifact(vm, "UniswapV2Factory.json", abi.encode(deployer));
        address routerA =
            UniswapArtifactLib.deployFromArtifact(vm, "UniswapV2Router02.json", abi.encode(factoryA, weth));
        address routerB =
            UniswapArtifactLib.deployFromArtifact(vm, "UniswapV2Router02.json", abi.encode(factoryB, weth));

        MyToken tokenA = new MyToken("MyToken A", "MTKA", deployer, SUPPLY);
        MyToken tokenB = new MyToken("MyToken B", "MTKB", deployer, SUPPLY);
        address a = address(tokenA);
        address b = address(tokenB);

        address pairA = IUniFactory(factoryA).createPair(a, b);
        IUniFactory(factoryB).createPair(a, b);

        uint256 deadline = block.timestamp + 1 hours;

        _addPool(routerA, a, b, 10_000 * 1e18, 25_000 * 1e18, deployer, deadline);
        _addPool(routerB, a, b, 10_000 * 1e18, 50_000 * 1e18, deployer, deadline);

        FlashArbitrage arb = new FlashArbitrage(factoryA, a, b);

        address[] memory path = new address[](2);
        path[0] = a;
        path[1] = b;
        uint256 minB = (IUniRouter(routerB).getAmountsOut(BORROW_A, path)[1] * 90) / 100;

        uint256 bBefore = IERC20(b).balanceOf(deployer);
        arb.executeFlash(pairA, BORROW_A, routerB, routerA, minB, deadline);
        uint256 bAfter = IERC20(b).balanceOf(deployer);

        assertGt(bAfter, bBefore, "deployer should receive surplus tokenB");
        console2.log("surplus B wei", bAfter - bBefore);
    }

    function _addPool(
        address router,
        address token0like,
        address token1like,
        uint256 amtA,
        uint256 amtB,
        address to,
        uint256 deadline
    ) internal {
        IERC20(token0like).approve(router, type(uint256).max);
        IERC20(token1like).approve(router, type(uint256).max);
        IUniRouter(router).addLiquidity(token0like, token1like, amtA, amtB, 1, 1, to, deadline);
    }
}
