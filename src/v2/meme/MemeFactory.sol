// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MemeToken} from "./MemeToken.sol";

/**
 * @title MemeFactory
 * @notice Meme 发射工厂：用最小代理克隆代币实现，降低发行者部署 Gas。
 * @dev
 * - 构造函数内部署唯一 `MemeToken` 实现合约，克隆均 delegatecall 至该实现。
 * - `mintMeme` 收取 ETH：`msg.value / 100` 给项目方，余款给对应 Meme 的 `creator`（发行者）。
 * - 应付金额 = `(perMint * price) / 10**decimals`：`perMint` 为最小单位个数，`price` 为每 1 完整代币的 wei。
 */
contract MemeFactory is ReentrancyGuard {
    /// @notice 已部署的 MemeToken 逻辑合约地址，供 `Clones.clone` 使用
    address public immutable implementation;
    /// @notice 项目方收款地址，收取每笔铸造费的 1%（整数除法向下取整）
    address public immutable projectRecipient;

    /// @notice 由本工厂登记过的 Meme 代币地址，`mintMeme` 仅允许对这些地址操作
    mapping(address => bool) public isMeme;

    /**
     * @notice 部署工厂并创建 MemeToken 实现；实现合约的 `FACTORY` 指向本合约
     * @param projectRecipient_ 项目方 ETH 收款地址，不可为零地址
     */
    constructor(address projectRecipient_) {
        require(projectRecipient_ != address(0), "MemeFactory: zero recipient");
        projectRecipient = projectRecipient_;
        implementation = address(new MemeToken(address(this)));
    }

    /**
     * @notice 发行者创建新的 Meme ERC20（最小代理实例）
     * @param symbol 代币代号（名称在代币内固定为 "Meme"）
     * @param totalSupply 总发行量上限（最小单位）
     * @param perMint 每次 `mintMeme` 铸造的数量（最小单位）
     * @param price 每个完整代币（10**decimals 单位）对应的 wei 单价
     * @return token 新克隆合约地址
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
    }

    /**
     * @notice 用户支付 ETH 购买一整批 Meme：铸造 `perMint` 给调用者，并按比例分账
     * @dev
     * - `msg.value` 必须严格等于本代币的 `(perMint * price) / 10**decimals`。
     * - 先更新代币状态再转 ETH，并配合 `nonReentrant` 降低重入风险。
     * @param tokenAddr 由本工厂 `deployMeme` 部署的代币地址
     */
    function mintMeme(address tokenAddr) external payable nonReentrant {
        require(isMeme[tokenAddr], "MemeFactory: unknown meme");
        MemeToken token = MemeToken(tokenAddr);
        // 与 MemeToken 注释一致：按「完整代币」计价折算本次应付 wei
        uint256 cost = (token.perMint() * token.price()) / (10 ** uint256(token.decimals()));
        require(msg.value == cost, "MemeFactory: wrong payment");

        // 1% 项目方，其余给发行者（整数除法下余数归发行者）
        uint256 platformFee = msg.value / 100;
        uint256 creatorShare = msg.value - platformFee;

        token.mint(msg.sender);

        (bool okP,) = projectRecipient.call{value: platformFee}("");
        require(okP, "MemeFactory: platform transfer failed");
        (bool okC,) = token.creator().call{value: creatorShare}("");
        require(okC, "MemeFactory: creator transfer failed");
    }
}
