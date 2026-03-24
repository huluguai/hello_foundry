// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

/**
 * @title TokenBankV2
 * @dev 面向标准 ERC20（含 OpenZeppelin ERC20Permit）。deposit / withdraw / permitDeposit 的 amount 均为最小单位。
 * @dev depositWithPermit2 使用 Uniswap Permit2 Allowance Transfer：用户需先对 Permit2 合约 ERC20 approve，再签 PermitSingle（spender 为本合约）。
 */
contract TokenBankV2 {
    IERC20Metadata public immutable token;
    IPermit2 public immutable permit2;

    mapping(address => uint256) public deposits;
    address[] public depositors;
    mapping(address => bool) public hasDeposited;

    event Deposit(address indexed user, uint256 amount, uint256 timestamp);
    event Withdraw(address indexed user, uint256 amount, uint256 timestamp);

    constructor(address _tokenAddress, address _permit2) {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_permit2 != address(0), "Invalid permit2 address");
        token = IERC20Metadata(_tokenAddress);
        permit2 = IPermit2(_permit2);
    }

    /**
     * @notice 存入代币（最小单位）
     * @dev 需先 approve 本合约
     */
    function deposit(uint256 amount) external returns (bool) {
        require(amount > 0, "Deposit amount must be greater than 0");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient token balance");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        deposits[msg.sender] += amount;
        if (!hasDeposited[msg.sender]) {
            hasDeposited[msg.sender] = true;
            depositors.push(msg.sender);
        }
        emit Deposit(msg.sender, amount, block.timestamp);
        return true;
    }

    /**
     * @notice 取款（最小单位）
     */
    function withdraw(uint256 amount) external returns (bool) {
        require(amount > 0, "Withdraw amount must be greater than 0");
        require(deposits[msg.sender] >= amount, "Insufficient deposit balance");
        unchecked {
            deposits[msg.sender] -= amount;
        }
        require(token.transfer(msg.sender, amount), "Transfer failed");
        if (deposits[msg.sender] == 0) {
            hasDeposited[msg.sender] = false;
        }
        emit Withdraw(msg.sender, amount, block.timestamp);
        return true;
    }

    /**
     * @notice EIP-2612 离线授权后由第三方代调存款
     * @param owner 签名者 / 代币持有者
     * @param amount 存入数量（最小单位，与 permit 中 value 一致）
     */
    function permitDeposit(
        address owner,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool) {
        // 1) 存入数量必须为正，避免无意义的 permit/transferFrom 与状态写入
        require(amount > 0, "Deposit amount must be greater than 0");
        // 2) owner 即链下签名中的代币持有者，零地址无法持有代币也无法合法签名通过 permit
        require(owner != address(0), "Invalid owner");
        // 3) 链上校验余额：若不足则不要签发 permit，避免 permit 成功但 transferFrom 因余额失败（浪费 gas、体验差）
        require(token.balanceOf(owner) >= amount, "Insufficient token balance");

        // 4) 在代币合约上执行 EIP-2612：验证 (v,r,s) 是否为 owner 对「授权本合约 spender 额度 amount、在 deadline 前有效」的签名，并写入 allowance(owner, bank)
        IERC20Permit(address(token)).permit(owner, address(this), amount, deadline, v, r, s);
        // 5) 本合约作为被授权方，从 owner 划扣 amount 到本合约地址（与 permit 里的 value 一致，单位均为最小单位）
        require(token.transferFrom(owner, address(this), amount), "Transfer failed");

        // 6) 在 Bank 账本中累加该用户在 Vault 中的存款（仍为最小单位）
        deposits[owner] += amount;
        // 7) 若是首次存款，记入存款人列表便于遍历统计
        if (!hasDeposited[owner]) {
            hasDeposited[owner] = true;
            depositors.push(owner);
        }
        // 8) 发出存款事件，供链下索引；permit 已消耗 allowance，通常额度归零或按代币实现扣减
        emit Deposit(owner, amount, block.timestamp);
        // 9) 与 deposit/withdraw 一致，返回 true 表示整笔流程成功
        return true;
    }

    /**
     * @notice Permit2 签名授权后存款（最小单位，与 permitSingle.details.amount 一致）
     * @param owner 代币持有者 / Permit2 签名者
     * @param permitSingle EIP-712 签名的单代币授权（details.token、spender 须与本合约及构造函数 token 一致）
     * @param signature owner 对 permitSingle 的签名
     * @dev 生产环境须先 token.approve(permit2, …)；链下 domain.verifyingContract 为 Permit2 地址。
     */
    function depositWithPermit2(
        address owner,
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature
    ) external returns (bool) {
        uint256 amount = uint256(permitSingle.details.amount);
        require(amount > 0, "Deposit amount must be greater than 0");
        require(owner != address(0), "Invalid owner");
        require(permitSingle.details.token == address(token), "Token mismatch");
        require(permitSingle.spender == address(this), "Spender must be bank");
        require(token.balanceOf(owner) >= amount, "Insufficient token balance");

        permit2.permit(owner, permitSingle, signature);
        permit2.transferFrom(owner, address(this), permitSingle.details.amount, address(token));

        deposits[owner] += amount;
        if (!hasDeposited[owner]) {
            hasDeposited[owner] = true;
            depositors.push(owner);
        }
        emit Deposit(owner, amount, block.timestamp);
        return true;
    }

    function getDepositBalance(address user) external view returns (uint256) {
        return deposits[user] / (10 ** uint256(token.decimals()));
    }

    function getAllDepositors() external view returns (address[] memory) {
        return depositors;
    }

    function getDepositorsCount() external view returns (uint256) {
        return depositors.length;
    }

    function getTotalBalance() external view returns (uint256) {
        return token.balanceOf(address(this)) / (10 ** uint256(token.decimals()));
    }
}
