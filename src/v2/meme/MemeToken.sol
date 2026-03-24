// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title MemeToken
 * @notice 单份逻辑实现合约，经工厂以 EIP-1167 最小代理克隆；每个克隆地址拥有独立存储。
 * @dev
 * - `totalSupply()` 符合 ERC20：当前已铸造的代币总量（最小单位）。
 * - `maxSupply` 对应工厂 `deployMeme` 的 `totalSupply` 参数，即发行硬顶。
 * - `price` 语义与工厂一致：每 **1 枚完整代币**（10**decimals 个最小单位）应付的 wei。
 */
contract MemeToken is Initializable {
    /// @notice 唯一允许调用 `initialize` / `mint` 的工厂合约地址（实现合约构造时写入，克隆通过 delegatecall 共用该 immutable）
    address public immutable FACTORY;

    /// @notice ERC20 名称，初始化时写死为 "Meme"
    string public name;
    /// @notice ERC20 代号，由发行者在 deploy 时传入
    string public symbol;
    /// @notice 小数位，固定 18
    uint8 public constant decimals = 18;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @notice 最大可铸造量（最小单位），达到后无法再 mint
    uint256 public maxSupply;
    /// @notice 每次通过工厂 `mintMeme` 铸造的代币数量（最小单位）
    uint256 public perMint;
    /// @notice 单价：每 1 完整代币对应的 wei（与工厂计算应付 ETH 一致）
    uint256 public price;
    /// @notice Meme 发行者（deployMeme 调用者），铸造费中除平台抽成外的收款方
    address public creator;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @param factory_ 部署本逻辑合约的 MemeFactory，克隆上的调用均视为来自该地址
    constructor(address factory_) {
        FACTORY = factory_;
        // 锁定逻辑合约本身，防止有人直接当 ERC20 使用未初始化的实现地址
        _disableInitializers();
    }

    /**
     * @notice 每个克隆部署后由工厂调用一次，完成参数写入
     * @param symbol_ 代币代号
     * @param maxSupply_ 总发行量上限（最小单位）
     * @param perMint_ 单次铸造数量（最小单位）
     * @param price_ 每完整代币的 wei 定价
     * @param creator_ 发行者地址，用于接收铸造分成
     */
    function initialize(
        string memory symbol_,
        uint256 maxSupply_,
        uint256 perMint_,
        uint256 price_,
        address creator_
    ) external initializer {
        require(msg.sender == FACTORY, "MemeToken: not factory");
        name = "Meme";
        symbol = symbol_;
        maxSupply = maxSupply_;
        perMint = perMint_;
        price = price_;
        creator = creator_;
    }

    /// @notice 已铸造代币总量（最小单位），与 ERC20 `totalSupply` 语义一致
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "MemeToken: insufficient allowance");
            unchecked {
                _approve(from, msg.sender, currentAllowance - amount);
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @notice 由工厂在用户付款后调用，向购买者铸造一整批 `perMint`
     * @dev 若剩余额度不足一整批则 revert，保证每次成功铸造量恒为 `perMint`
     * @param to 接收新铸代币的地址（一般为购买者）
     */
    function mint(address to) external {
        require(msg.sender == FACTORY, "MemeToken: not factory");
        require(_totalSupply + perMint <= maxSupply, "MemeToken: cap exceeded");

        unchecked {
            _totalSupply += perMint;
        }
        _balances[to] += perMint;
        emit Transfer(address(0), to, perMint);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "MemeToken: transfer from zero");
        require(to != address(0), "MemeToken: transfer to zero");
        require(_balances[from] >= amount, "MemeToken: insufficient balance");

        unchecked {
            _balances[from] -= amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "MemeToken: approve from zero");
        require(spender != address(0), "MemeToken: approve to zero");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}
