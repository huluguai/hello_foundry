// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MyToken - 自定义 ERC20 代币合约
 * @dev 实现完整的 ERC20 标准接口，包含铸造和燃烧功能
 */
contract MyToken {
    // ==================== 代币基本信息 ====================
    
    /// @notice 代币名称
    string public name = "MyToken";
    
    /// @notice 代币符号（交易对中使用）
    
    string public symbol = "MTK";
    
    /// @notice 代币精度（小数位数），18 是以太坊标准
    uint8 public decimals = 18;
    
    /// @notice 代币总供应量
    uint256 public totalSupply;
    
    // ==================== 状态变量 ====================
    
    /// @notice 记录每个地址的代币余额
    mapping(address => uint256) public balanceOf;
    
    /// @notice 授权额度映射
    mapping(address => mapping(address => uint256)) public allowance;
    
    /// @notice 合约所有者（只有 owner 可以铸造新币）
    address public owner;
    
    // ==================== 事件定义 ====================
    
    /// @notice 转账事件
    /// @param from 转出地址（索引字段，便于查询）
    /// @param to 转入地址（索引字段）
    /// @param value 转账金额（最小单位）
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    /// @notice 授权事件
    /// @param owner 代币所有者（索引字段）
    /// @param spender 被授权地址（索引字段）
    /// @param value 授权额度
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    // ==================== 构造函数 ====================
    
    /**
     * @notice 合约部署时执行一次
     * @dev 将所有初始代币分配给部署者，并设置 owner
     * @param _initialSupply 初始供应量（以代币为单位，会自动转换为最小单位）
     */
    constructor(uint256 _initialSupply) {
        // 将用户友好的供应量转换为带精度的实际数量
        // 例如：1000000 代币 * 10^18 = 实际存储的数量
        totalSupply = _initialSupply * (10 ** uint256(decimals));
        
        // 将所有代币分配给合约部署者
        balanceOf[msg.sender] = totalSupply;
        
        // 设置部署者为合约所有者
        owner = msg.sender;
        
        // 发起量事件，from 为零地址表示这是铸造行为
        emit Transfer(address(0), msg.sender, totalSupply);
    }
    
    // ==================== 修饰器 ====================
    
    /**
     * @notice 限制只有 owner 才能调用的函数修饰器
     * @dev 用于保护铸币等敏感操作
     */
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() internal view {
        require(msg.sender == owner, "Only owner can call this function");
    }
    
    // ==================== ERC20 核心功能 ====================
    
    /**
     * @notice 向指定地址转账
     * @dev ERC20 标准的核心功能
     * @param to 接收方地址
     * @param value 转账金额（代币单位，会自动转换）
     * @return 是否成功
     */
    function transfer(address to, uint256 value) external returns (bool) {
        // 防止转账到零地址
        require(to != address(0), "Transfer to zero address");
        
        // 将代币单位转换为最小单位（带精度）
        uint256 valueInWei = value * (10 ** uint256(decimals));
        
        // 检查余额是否充足
        require(balanceOf[msg.sender] >= valueInWei, "Insufficient balance");
        
        // 更新双方余额
        unchecked {
            balanceOf[msg.sender] -= valueInWei;
            balanceOf[to] += valueInWei;
        }
        
        // 发出转账事件
        emit Transfer(msg.sender, to, valueInWei);
        
        return true;
    }
    
    /**
     * @notice 授权其他地址使用自己的代币
     * @dev 常用于 DEX、借贷协议等场景
     * @param spender 被授权的地址
     * @param value 授权额度（代币单位）
     * @return 是否成功
     */
    function approve(address spender, uint256 value) external returns (bool) {
        // 防止授权给零地址
        require(spender != address(0), "Approve to zero address");
        
        // 将代币单位转换为最小单位
        uint256 valueInWei = value * (10 ** uint256(decimals));
        
        // 检查用户余额是否足够覆盖授权额度
        require(balanceOf[msg.sender] >= valueInWei, "Insufficient balance for approval");
        
        // 设置授权额度
        allowance[msg.sender][spender] = valueInWei;
        
        // 发出授权事件
        emit Approval(msg.sender, spender, valueInWei);
        
        return true;
    }
    
    /**
     * @notice 代他人转账（需要预先授权）
     * @dev ERC20 的关键功能，用于第三方合约调用
     * @param from 代币持有者地址
     * @param to 接收方地址
     * @param value 转账金额（代币单位）
     * @return 是否成功
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        // 防止转账到零地址
        require(to != address(0), "Transfer to zero address");
        
        // 确保调用者不是自己转账给自己
        require(from != msg.sender, "Use transfer instead of transferFrom for self");
        
        // 将代币单位转换为最小单位
        uint256 valueInWei = value * (10 ** uint256(decimals));
        
        // 检查 from 地址余额是否充足
        require(balanceOf[from] >= valueInWei, "Insufficient balance");
        
        // 检查授权额度是否足够
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= valueInWei, "Allowance exceeded");
        
        // 使用 unchecked 防止溢出（Solidity 0.8+ 已安全）
        unchecked {
            balanceOf[from] -= valueInWei;
            balanceOf[to] += valueInWei;
            allowance[from][msg.sender] = currentAllowance - valueInWei;
        }
        
        // 发出转账事件
        emit Transfer(from, to, valueInWei);
        
        return true;
    }
    
    // ==================== 扩展功能 ====================
    
    /**
     * @notice 铸造新代币（只有 owner 可以调用）
     * @dev 增加总供应量并将新币分配给调用者
     * @param amount 铸造数量（代币单位）
     * @return 是否成功
     */
    function mint(uint256 amount) external onlyOwner returns (bool) {
        // 转换为带精度的实际数量
        uint256 mintAmount = amount * (10 ** uint256(decimals));
        
        // 增加总供应量
        totalSupply += mintAmount;
        
        // 将新币分配给调用者（owner）
        balanceOf[msg.sender] += mintAmount;
        
        // 发出转账事件（从零地址表示铸造）
        emit Transfer(address(0), msg.sender, mintAmount);
        
        return true;
    }
    
    /**
     * @notice 燃烧自己的代币
     * @dev 永久减少代币供应量
     * @param amount 燃烧数量（代币单位）
     * @return 是否成功
     */
    function burn(uint256 amount) external returns (bool) {
        // 转换为带精度的实际数量
        uint256 burnAmount = amount * (10 ** uint256(decimals));
        
        // 检查余额是否足够燃烧
        require(balanceOf[msg.sender] >= burnAmount, "Insufficient balance for burning");
        
        // 减少余额和总供应量
        balanceOf[msg.sender] -= burnAmount;
        totalSupply -= burnAmount;
        
        // 发出转账事件（到零地址表示燃烧）
        emit Transfer(msg.sender, address(0), burnAmount);
        
        return true;
    }
}