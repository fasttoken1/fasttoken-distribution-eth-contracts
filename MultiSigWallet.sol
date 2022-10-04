
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


/// Openzeppelin imports
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';


contract MultiSigWallet {

    event SubmitTransaction(uint256 indexed txIndex);
    event ConfirmTransaction(uint256 indexed txIndex);
    event RevokeConfirmation(uint256 indexed txIndex);
    event ExecuteTransaction(uint256 indexed txIndex);

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public numberOfRequiredConfirmations;

    // mapping from transaction index => owner index => bool
    mapping(uint256 => mapping(uint256 => bool)) public isConfirmed;

    Transaction[] public transactions;

    enum TransactionType {
        ChangeOwner,
        Transfer,
        ERC20Transfer
    }

    struct Transaction {
        TransactionType transactionType;
        address address1;
        address address2;
        uint256 amount;
        bool executed;
        uint256 numberOfConfirmations;
    }

    modifier onlyOwner() {
        require(isOwner[msg.sender], 'not owner');
        _;
    }

    modifier transactionExists(uint256 _txIndex) {
        require(_txIndex < transactions.length, 'transaction does not exist');
        _;
    }

    modifier notExecuted(uint256 _txIndex) {
        require(!transactions[_txIndex].executed, 'transaction already executed');
        _;
    }

    modifier notConfirmed(uint256 _txIndex) {
        uint256 index = _ownerIndex(msg.sender);
        require(!isConfirmed[_txIndex][index], 'transaction already confirmed');
        _;
    }

    constructor(address[] memory _owners, uint256 _numberOfRequiredConfirmations) {

        require(_owners.length > 0, 'owners required');
        require(_numberOfRequiredConfirmations > 0 && _numberOfRequiredConfirmations <= _owners.length,
                'invalid number of required confirmations');

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];

            require(owner != address(0), 'invalid owner');
            require(!isOwner[owner], 'owner not unique');

            isOwner[owner] = true;
            owners.push(owner);
        }

        numberOfRequiredConfirmations = _numberOfRequiredConfirmations;
    }

    function submitTransaction(
            TransactionType _type,
            address _address1,
            address _address2,
            uint256 _value) public onlyOwner {

        bool a = _type == TransactionType.Transfer;
        bool b = address(0x0) == _address1;
        require(a == b, 'Wrong transactionType or address1');
        if (_type == TransactionType.ChangeOwner) {
            require(isOwner[_address1], 'address1 is not owner');
            require(! isOwner[_address2], 'address2 is already owner');
        }
        uint256 txIndex = transactions.length;
        transactions.push(Transaction(_type, _address1, _address2, _value, false, 0));

        emit SubmitTransaction(txIndex);
    }

    function confirmTransaction(uint256 _txIndex)
            public
            onlyOwner
            transactionExists(_txIndex)
            notExecuted(_txIndex)
            notConfirmed(_txIndex) {

        Transaction storage transaction = transactions[_txIndex];
        transaction.numberOfConfirmations += 1;
        uint256 index = _ownerIndex(msg.sender);
        isConfirmed[_txIndex][index] = true;

        emit ConfirmTransaction(_txIndex);
    }

    function executeTransaction(uint256 _txIndex)
            public
            onlyOwner
            transactionExists(_txIndex)
            notExecuted(_txIndex) {

        Transaction storage transaction = transactions[_txIndex];
        require(transaction.numberOfConfirmations >= numberOfRequiredConfirmations, 'cannot execute transaction');
        transaction.executed = true;
        if (TransactionType.ChangeOwner == transaction.transactionType) {
            require(! isOwner[transaction.address1], 'address1 must be owner');
            require(isOwner[transaction.address2], 'address2 cannot be owner');
            uint256 index = _ownerIndex(transaction.address1);
            owners[index] = transaction.address2;
            isOwner[transaction.address1] = false;
            isOwner[transaction.address2] = true;
        } else if (TransactionType.Transfer == transaction.transactionType) {
            (bool success, ) = transaction.address2.call{value: transaction.amount}('');
            require(success, 'transaction failed');
        } else {
            require(IERC20(transaction.address1).transfer(transaction.address2, transaction.amount), 'token transaction failed');
        }
        emit ExecuteTransaction(_txIndex);
    }

    function revokeConfirmation(uint256 _txIndex)
            public
            onlyOwner
            transactionExists(_txIndex)
            notExecuted(_txIndex) {

        Transaction storage transaction = transactions[_txIndex];

        uint256 index = _ownerIndex(msg.sender);
        require(isConfirmed[_txIndex][index], 'transaction not confirmed');

        transaction.numberOfConfirmations -= 1;
        isConfirmed[_txIndex][index] = false;

        emit RevokeConfirmation(_txIndex);
    }

    function getOwners() public view returns (address[] memory) {

        return owners;
    }

    function getTransactionCount() public view returns (uint256) {

        return transactions.length;
    }

    function getTransactions() public view returns (Transaction[] memory) {

        return transactions;
    }


    /// Helper member functions

    function _ownerIndex(address owner) private view returns (uint256) {

        for (uint256 i = 0; i < owners.length; ++i) {
            if (owner == owners[i]) {
                return i;
            }
        }
        revert('Wrong owner');
    }
}
