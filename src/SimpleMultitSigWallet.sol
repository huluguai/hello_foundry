// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;
/**
    @title SimpleMultitSigWallet
    @dev A simple multisignature wallet
 */
contract SimpleMultitSigWallet {
    // 事件定义
    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    event SubmitTransaction(uint256 indexed txId, address indexed destination, uint256 value,bytes data,address indexed proposer);
    event ConfirmTransaction(address indexed owner, uint256 indexed txId);
    event RevokeConfirmation(address indexed owner, uint256 indexed txId);
    event ExecuteTransaction(address indexed owner, uint256 indexed txId,bool success,bytes returnData);
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event RequirementChanged(uint256 required);

    // 状态变量定义
    // 多签持有人列表
    address[] public owners;
    // 地址是否为持有人
    mapping(address => bool) public isOwner;
    // 多签所需的确认数
    uint256 public required;

    // 交易结构
    struct Transaction {
        // 目标地址
        address destination;
        // 转账金额(单位: wei)
        uint256 value;
        // 调用数据
        bytes data;
        // 是否已执行
        bool executed;
        // 确认者数量
        uint256 numConfirmations;
    }
    // 所有提案列表
    Transaction[] public transactions;
    // 确认状态映射: 交易Id -> 持有人地址 -> 是否确认
    mapping(uint256 => mapping(address => bool)) public confirmations;
    // 修饰器
    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }
    modifier txExists(uint256 _txId){
        require(_txId < transactions.length, "Transaction does not exist");
        _;
    }
    modifier notExecuted(uint256 _txId){
        require(!transactions[_txId].executed, "Transaction already executed");
        _;
    }
    modifier notConfirmed(uint256 _txId){
        require(!confirmations[_txId][msg.sender], "Transaction already confirmed");
        _;
    }
    // 构造函数
    /**
    * @param _owners 初始化所有人
    * @param _required 初始化所需的确认数
    * @dev 初始化所有人并设置所需的确认数
     */
    constructor(address[] memory _owners, uint256 _required){
        require(_owners.length > 0, "Owners required");
        require(_required > 0 && _required <= _owners.length, "Invalid required number of confirmations");
        //初始化所有人
        for(uint256 i = 0; i < _owners.length; i++){
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner not unique");
            isOwner[owner] = true;
            owners.push(owner);
        }
        required = _required;
        emit RequirementChanged(_required);
    }


    // 接收ETH
    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    /**
    * @dev 多签持有人提交交易提案
    * @param _destination 目标地址
    * @param _value 转账金额
    * @param _data 调用数据
    * @return 交易ID
     */
     function submitTransaction(address _destination, uint256 _value, bytes memory _data) external onlyOwner returns (uint256) { 
        require(_destination != address(0), "Invalid destination");
        // 允许以下组合：
        // 1. value > 0 且 data 为空：纯 ETH 转账
        // 2. value == 0 且 data 不为空：函数调用
        // 3. value > 0 且 data 不为空：ETH 转账 + 函数调用
        require(_value > 0 || _data.length > 0, "Either value or data must be provided");
        uint256 txId = transactions.length;
        transactions.push(Transaction({
            destination: _destination,
            value: _value,
            data: _data,
            executed: false,
            numConfirmations: 0
        }));
        emit SubmitTransaction(txId, _destination, _value, _data, msg.sender);

        // 提交者自动确认该交易
        confirmTransaction(txId);
        return txId;
     }

    /**
    * @dev 多签持有人确认交易提案
    * @param _txId 交易ID
    */
    function confirmTransaction(uint256 _txId) public onlyOwner txExists(_txId) notExecuted(_txId) notConfirmed(_txId) {
        confirmations[_txId][msg.sender] = true; // 确认交易
        transactions[_txId].numConfirmations += 1;
        emit ConfirmTransaction(msg.sender, _txId);
    }

    /**
    * @dev 多签持有人撤销确认交易提案
    * @param _txId 交易ID
    */
    function revokeConfirmation(uint256 _txId) external onlyOwner txExists(_txId) notExecuted(_txId) {
        require(confirmations[_txId][msg.sender], "Transaction not confirmed");
        confirmations[_txId][msg.sender] = false;
        transactions[_txId].numConfirmations -= 1;
        emit RevokeConfirmation(msg.sender, _txId);
    }

    /**
    * @dev 执行已获得足够确认的交易(任何人都可以调用)
    * @param _txId 交易ID
    */
    function executeTransaction(uint256 _txId) external txExists(_txId) notExecuted(_txId) {
        require(transactions[_txId].numConfirmations >= required, "Not enough confirmations");
        require(transactions[_txId].executed == false, "Transaction already executed"); // 防止重复执行
        Transaction storage txData = transactions[_txId];
        // 设置交易为已执行
        txData.executed = true; 
        (bool success, bytes memory returnData) = txData.destination.call{value: txData.value}(txData.data);
        emit ExecuteTransaction(msg.sender, _txId, success, returnData);
        require(success, "Transaction execution failed");
    }

    /**
    * @dev 添加新的多签持有人
    * @param _owner 新的持有人地址
    */
    function addOwner(address _owner) external {
        require(msg.sender == address(this), "Only contract itself can add owners");
        require(_owner != address(0), "Invalid owner");
        require(!isOwner[_owner], "Owner already exists");
        isOwner[_owner] = true;
        owners.push(_owner);
        emit OwnerAdded(_owner);
    }
    /**
    * @dev 删除多签持有人
    * @param _owner 要删除的持有人地址
    */
    function removeOwner(address _owner) external {
        require(msg.sender == address(this), "Only contract itself can remove owners");
        require(isOwner[_owner], "Owner does not exist");
        require(owners.length > 1, "At least one owner is required");
        isOwner[_owner] = false;
        // 持有人列表中移除
        for(uint256 i = 0; i < owners.length; i++){
            if(owners[i] == _owner){
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        //调整所需确认数
        if(required > owners.length){
            required = owners.length;
            emit RequirementChanged(required);
        }
        emit OwnerRemoved(_owner);
    }

    /**
    * @dev 修改多签所需的确认数
    * @param _newRequired 新的确认数
    */
    function changeRequirement(uint256 _newRequired) external onlyOwner {
        require(_newRequired > 0 && _newRequired <= owners.length, "Invalid required number of confirmations");
        required = _newRequired;
        emit RequirementChanged(_newRequired);
    }
    // 视图函数

    /**
    * @dev 获取持有人列表
    * @return 持有人列表
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }       
    /**
    * @dev 获取交易数量
    * @return 交易数量
     */
    function getTransactions() external view returns (uint256) {
        return transactions.length;
    }
    /**
    * @dev 获取交易详情
    * @param _txId 交易ID
    * @return 交易目标地址, 交易金额, 交易数据, 是否已执行, 确认者数量
     */
    function getTransaction(uint256 _txId) external view returns (address, uint256, bytes memory, bool, uint256) {
        Transaction storage txData = transactions[_txId];
        return (txData.destination, txData.value, txData.data, txData.executed, txData.numConfirmations);
    }

    /**
    * @dev 获取合约ETH余额
    * @return 合约ETH余额
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}