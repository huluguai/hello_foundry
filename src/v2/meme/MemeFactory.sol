// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MemeToken} from "./MemeToken.sol";
import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "./interfaces/IUniswapV2.sol";

/**
 * @title MemeFactory
 * @notice Meme 发射工厂：最小代理克隆 `MemeToken`；铸造费的 5% ETH 与同比例的代币经 Uniswap V2 加池，LP 记给 `projectRecipient`；约 95% ETH 给发行者。
 * @dev
 * - 应付单笔铸造：`msg.value == (perMint * price) / 10**decimals`，`price` 为每 1 完整代币的 wei。
 * - `buyMeme`：若池价优于上述 mint 隐含价则通过 Router swap。
 */
contract MemeFactory is ReentrancyGuard {
    /// @notice 流动性占单笔支付 ETH 的比例（5%）
    uint256 internal constant LIQUIDITY_BPS = 5;
    uint256 internal constant BPS_DENOM = 100;
    /// @notice `addLiquidity` 最小边：期望值的 99%（基点内再取整）
    uint256 internal constant SLIPPAGE_BPS = 99;

    /// @notice `MemeToken` 逻辑合约，供 `Clones.clone` 使用
    address public immutable implementation;
    /// @notice 接收 Uniswap V2 LP 代币的项目方地址（不接收铸造费 ETH）
    address public immutable projectRecipient;
    /// @notice Uniswap V2 Router
    IUniswapV2Router02 public immutable uniswapRouter;

    mapping(address => bool) public isMeme;

    event MemeDeployed(
        address indexed token, address indexed creator, string symbol, uint256 maxSupply, uint256 perMint, uint256 price
    );
    event MemeMinted(
        address indexed tokenAddr,
        address indexed buyer,
        uint256 perMinted,
        uint256 tokenForLp,
        uint256 liquidityEth,
        uint256 creatorShare
    );
    event LiquidityAdded(
        address indexed tokenAddr, uint256 tokenAmount, uint256 ethAmount, address indexed lpRecipient
    );
    event MemeBought(
        address indexed tokenAddr, address indexed buyer, uint256 ethIn, uint256 amountOutMin, uint256 amountOut
    );

    /**
     * @param projectRecipient_ 接收 `addLiquidityETH` 所铸造 LP 的地址
     * @param uniswapRouter_ Uniswap V2 Router
     */
    constructor(address projectRecipient_, address uniswapRouter_) {
        require(projectRecipient_ != address(0), "MemeFactory: zero recipient");
        require(uniswapRouter_ != address(0), "MemeFactory: zero router");
        projectRecipient = projectRecipient_;
        uniswapRouter = IUniswapV2Router02(uniswapRouter_);
        implementation = address(new MemeToken(address(this)));
    }

    /**
     * @notice 发行者创建新的 Meme（最小代理实例）
     */
    function deployMeme(
        string memory symbol,
        uint256 totalSupply,
        uint256 perMint,
        uint256 price
    ) external returns (address token) {
        require(totalSupply > 0 && perMint > 0 && perMint <= totalSupply, "MemeFactory: invalid params");
        token = Clones.clone(implementation);
        MemeToken(token).initialize(symbol, totalSupply, perMint, price, msg.sender);
        isMeme[token] = true;
        emit MemeDeployed(token, msg.sender, symbol, totalSupply, perMint, price);
    }

    /**
     * @notice 支付固定 ETH 铸造一整批 `perMint`；5% 与同比例代币加池（LP 给项目方），余 ETH 给 `creator`
     */
    function mintMeme(address tokenAddr) external payable nonReentrant {
        require(isMeme[tokenAddr], "MemeFactory: unknown meme");
        MemeToken token = MemeToken(tokenAddr);
        uint256 cost = (token.perMint() * token.price()) / (10 ** uint256(token.decimals()));
        require(msg.value == cost, "MemeFactory: wrong payment");

        uint256 liquidityEth = (msg.value * LIQUIDITY_BPS) / BPS_DENOM;
        uint256 creatorShare = msg.value - liquidityEth;

        uint256 tokenForLp = 0;
        if (liquidityEth > 0) {
            tokenForLp = (liquidityEth * (10 ** uint256(token.decimals()))) / token.price();
            require(tokenForLp > 0, "MemeFactory: lp token round down");
        }

        uint256 supply = token.totalSupply();
        uint256 cap = token.maxSupply();
        require(supply + token.perMint() + tokenForLp <= cap, "MemeToken: cap exceeded");

        token.mint(msg.sender);

        if (tokenForLp > 0) {
            token.mintTo(address(this), tokenForLp);
            uint256 amountTokenMin = (tokenForLp * SLIPPAGE_BPS) / BPS_DENOM;
            uint256 amountETHMin = (liquidityEth * SLIPPAGE_BPS) / BPS_DENOM;
            require(token.approve(address(uniswapRouter), tokenForLp), "MemeFactory: approve failed");

            uniswapRouter.addLiquidityETH{value: liquidityEth}(
                tokenAddr,
                tokenForLp,
                amountTokenMin,
                amountETHMin,
                projectRecipient,
                block.timestamp + 300
            );
            emit LiquidityAdded(tokenAddr, tokenForLp, liquidityEth, projectRecipient);
        }

        (bool okC,) = token.creator().call{value: creatorShare}("");
        require(okC, "MemeFactory: creator transfer failed");

        emit MemeMinted(tokenAddr, msg.sender, token.perMint(), tokenForLp, liquidityEth, creatorShare);
    }

    /**
     * @notice 当 Uniswap 同样 ETH 所得代币多于 mint 隐含价时，通过 Router 买入 Meme
     * @param amountOutMin 最小接受输出（防夹）
     * @param deadline Router 截止时间
     */
    function buyMeme(address tokenAddr, uint256 amountOutMin, uint256 deadline) external payable nonReentrant {
        require(isMeme[tokenAddr], "MemeFactory: unknown meme");
        require(msg.value > 0, "MemeFactory: zero eth");
        require(deadline >= block.timestamp, "MemeFactory: expired");

        _requireMemePairLiquidity(tokenAddr);

        MemeToken token = MemeToken(tokenAddr);
        address[] memory path = _wethToMemePath(tokenAddr);
        uint256 expectedOut = uniswapRouter.getAmountsOut(msg.value, path)[1];
        require(
            expectedOut > _mintBaselineTokenOut(token, msg.value), "MemeFactory: mint price better or equal"
        );

        uint256 outAmt = uniswapRouter.swapExactETHForTokens{value: msg.value}(
            amountOutMin, path, msg.sender, deadline
        )[1];

        emit MemeBought(tokenAddr, msg.sender, msg.value, amountOutMin, outAmt);
    }

    function _mintBaselineTokenOut(MemeToken token, uint256 ethIn) private view returns (uint256) {
        return (ethIn * (10 ** uint256(token.decimals()))) / token.price();
    }

    function _wethToMemePath(address tokenAddr) private view returns (address[] memory path) {
        path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = tokenAddr;
    }

    function _requireMemePairLiquidity(address tokenAddr) private view {
        address pair = IUniswapV2Factory(uniswapRouter.factory()).getPair(tokenAddr, uniswapRouter.WETH());
        require(pair != address(0), "MemeFactory: no pair");
        (uint112 r0, uint112 r1,) = IUniswapV2Pair(pair).getReserves();
        address t0 = IUniswapV2Pair(pair).token0();
        uint256 reserveToken = tokenAddr == t0 ? uint256(r0) : uint256(r1);
        uint256 reserveWeth = tokenAddr == t0 ? uint256(r1) : uint256(r0);
        require(reserveToken > 0 && reserveWeth > 0, "MemeFactory: no liquidity");
    }

    receive() external payable {}
}
