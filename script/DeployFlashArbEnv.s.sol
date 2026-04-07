// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
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

/// @notice Deploys two Uniswap V2 stacks from npm artifacts, two ERC20s, PoolA/PoolB, FlashArbitrage; optional flash (RUN_FLASH_SWAP=1).
contract DeployFlashArbEnv is Script {
    uint256 internal constant SUPPLY = 10_000_000 * 1e18;

    uint256 internal constant POOL_A_A = 10_000 * 1e18;
    uint256 internal constant POOL_A_B = 25_000 * 1e18;

    uint256 internal constant POOL_B_A = 10_000 * 1e18;
    uint256 internal constant POOL_B_B = 50_000 * 1e18;

    uint256 internal constant BORROW_A = 500 * 1e18;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        bool doFlash = _envBool("RUN_FLASH_SWAP");

        vm.startBroadcast(pk);

        address weth = UniswapArtifactLib.deployFromArtifact(vm, "WETH9.json", bytes(""));
        address factoryA = UniswapArtifactLib.deployFromArtifact(vm, "UniswapV2Factory.json", abi.encode(deployer));
        address factoryB = UniswapArtifactLib.deployFromArtifact(vm, "UniswapV2Factory.json", abi.encode(deployer));
        address routerA =
            UniswapArtifactLib.deployFromArtifact(vm, "UniswapV2Router02.json", abi.encode(factoryA, weth));
        address routerB =
            UniswapArtifactLib.deployFromArtifact(vm, "UniswapV2Router02.json", abi.encode(factoryB, weth));

        MyToken tokenA = new MyToken("MyToken A", "MTKA", deployer, SUPPLY);
        MyToken tokenB = new MyToken("MyToken B", "MTKB", deployer, SUPPLY);

        address pairA = IUniFactory(factoryA).createPair(address(tokenA), address(tokenB));
        IUniFactory(factoryB).createPair(address(tokenA), address(tokenB));

        uint256 deadline = block.timestamp + 1 hours;

        IERC20(address(tokenA)).approve(routerA, type(uint256).max);
        IERC20(address(tokenB)).approve(routerA, type(uint256).max);
        IUniRouter(routerA).addLiquidity(
            address(tokenA), address(tokenB), POOL_A_A, POOL_A_B, 1, 1, deployer, deadline
        );

        IERC20(address(tokenA)).approve(routerB, type(uint256).max);
        IERC20(address(tokenB)).approve(routerB, type(uint256).max);
        IUniRouter(routerB).addLiquidity(
            address(tokenA), address(tokenB), POOL_B_A, POOL_B_B, 1, 1, deployer, deadline
        );

        FlashArbitrage arb = new FlashArbitrage(factoryA, address(tokenA), address(tokenB));

        console2.log("WETH9", weth);
        console2.log("factoryA_PoolA", factoryA);
        console2.log("factoryB_PoolB", factoryB);
        console2.log("routerA", routerA);
        console2.log("routerB", routerB);
        console2.log("tokenA", address(tokenA));
        console2.log("tokenB", address(tokenB));
        console2.log("pairA", pairA);
        console2.log("FlashArbitrage", address(arb));

        if (doFlash) {
            address[] memory path = new address[](2);
            path[0] = address(tokenA);
            path[1] = address(tokenB);
            uint256[] memory outs = IUniRouter(routerB).getAmountsOut(BORROW_A, path);
            uint256 minB = (outs[1] * 90) / 100;
            console2.log("flash borrow A", BORROW_A);
            console2.log("min B out (90pct)", minB);
            arb.executeFlash(pairA, BORROW_A, routerB, routerA, minB, deadline);
            console2.log("flash swap completed");
        }

        vm.stopBroadcast();
    }

    function _envBool(string memory name) private view returns (bool) {
        try vm.envString(name) returns (string memory v) {
            bytes32 h = keccak256(bytes(v));
            return h == keccak256("1") || h == keccak256("true") || h == keccak256("yes");
        } catch {
            return false;
        }
    }
}
