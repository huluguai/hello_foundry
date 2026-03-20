// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {XZXToken} from "../src/v2/mytoken/xzx_token.sol";
import {TokenBankV2} from "../src/v2/mytoken/token_bank_v2.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title TokenBankV2PermitTest
 * @dev 演示 EIP-2612：用户(owner)链下签名，第三方(relayer)代调 permitDeposit，模拟「赞助 gas」场景。
 */
contract TokenBankV2PermitTest is Test {
    XZXToken internal token;
    TokenBankV2 internal bank;

    /// @dev 测试用私钥，对应「持币用户」EOA；生产环境由真实钱包签名，不会在测试里写死私钥。
    uint256 internal constant OWNER_PK = 0xA11CE;
    /// @dev 签名者与存款账户（须一致，permit 验签要求 signer == owner）
    address internal owner;
    /// @dev 任意地址均可调用 permitDeposit；此处用 prank(relayer) 表示代付 gas 的提交者 ≠ owner
    address internal relayer;

    /// @dev 必须与 OpenZeppelin ERC20Permit 中 PERMIT_TYPEHASH 一致，否则链上 permit 会验签失败
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        owner = vm.addr(OWNER_PK);
        relayer = makeAddr("relayer");

        // 部署 XZX（整币初始供应 100 万）与 Bank
        token = new XZXToken(1_000_000);
        bank = new TokenBankV2(address(token));

        // 给 owner 一些 XZX，否则无法 transferFrom
        token.transfer(owner, 10_000 * 10 ** token.decimals());
    }

    /**
     * @notice 按 EIP-712 拼出 Permit 的签名字节（digest），与链上代币 DOMAIN_SEPARATOR 一致
     * @param tokenAddr 代币合约（verifyingContract 编码在 DOMAIN_SEPARATOR 里）
     * @param tokenOwner Permit.owner，须与签名私钥对应地址一致
     * @param spender 须为 Bank 地址，与 permitDeposit 里 address(this) 一致
     * @param value 最小单位，须与 permitDeposit 的 amount 一致
     * @param nonce 链上 token.nonces(owner)，防重放
     * @param deadline Unix 秒，须晚于执行区块时间
     */
    function _permitDigest(
        address tokenAddr,
        address tokenOwner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        // 类型化结构哈希（EIP-712）
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, tokenOwner, spender, value, nonce, deadline));
        // 从链上读域分隔符（含链 id、合约地址、name 等），勿手写 hex
        bytes32 domainSeparator = IERC20Permit(tokenAddr).DOMAIN_SEPARATOR();
        // 0x19 0x01 前缀 + domain + struct => 最终对 secp256k1 签名的哈希
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function testPermitDepositByRelayer() public {
        // 存款金额：最小单位（与业务合约 deposit/permitDeposit 语义一致）
        uint256 amount = 1_000 * 10 ** token.decimals();
        // 签名过期时间：须覆盖测试执行时刻
        uint256 deadline = block.timestamp + 1 days;
        // 当前 owner 在代币上的 permit nonce（首笔一般为 0）
        uint256 nonce = token.nonces(owner);

        // 链下等价步骤：构造 digest 并用 owner 私钥签名（不上链、不耗 gas）
        bytes32 digest = _permitDigest(address(token), owner, address(bank), amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        // relayer 发起交易：Gas 在真实链上由 relayer 付；这里仅模拟 msg.sender == relayer
        vm.prank(relayer);
        assertTrue(bank.permitDeposit(owner, amount, deadline, v, r, s));

        // Bank 账本与合约持币一致；标准 ERC20 在 transferFrom 后会把已用额度从 allowance 扣掉，故为 0
        assertEq(bank.deposits(owner), amount);
        assertEq(token.balanceOf(address(bank)), amount);
        assertEq(token.allowance(owner, address(bank)), 0);
    }
}
