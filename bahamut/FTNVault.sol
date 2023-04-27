
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;


/// Openzeppelin imports
import './Ownable.sol';

/**
 * Define the FTNVault contract, which inherits from the Ownable contract.
 * This contract will use the native token (FTN).
 * The purpose of this contract is to facilitate the transfer of erc20 FTN tokens from the Ethereum
 * mainnet to Sahara network as native FTN. Each time tokens are burned on the Ethereum blockchain,
 * an equivalent amount of native (FTN) will be transferred from this contract to the
 * corresponding recipient's address on Sahara. The contract also stores Ethereum
 * burn transaction hashes to prevent double-spending.
 */
contract FTNVault is Ownable {

    // Define the mapping to store Ethereum burn transaction hashes
    mapping(bytes32 => bool) public burnTransactionHashes;

    // Define the mapping to store miter limits
    mapping(address => uint256) public limits;

    // Indicates contract initialization
    bool public initialized;

    // Define the event that will be emitted when a new burn transaction is processed
    event BurnTransactionProcessed(bytes32 indexed burnTxHash, address indexed recipient, uint256 amount);

    // Define the event that will be emitted when a minter limit will be updated
    event LimitUpdated(address indexed minterAddress, uint256 amount);


    // Define the constructor to empty
    constructor() {

    }

    // Define the function which will initialize the FTNVault contract instead of constructor
    function initialize(bytes32 burnTxHash_) public {

        require(!initialized, 'Contract has already been initialized');
        initialized = true;

        _transferOwnership(msg.sender);
        burnTransactionHashes[burnTxHash_] = true;

        uint256 amount = 1000 * 10**18;
        emit BurnTransactionProcessed(burnTxHash_, msg.sender, amount);
    }

    // Updates minting limit of minter address
    function updateLimit(address minterAddress_, uint256 limit_) external onlyOwner {

        require(initialized, 'Contract has not been initialized');
        limits[minterAddress_] = limit_;
        emit LimitUpdated(minterAddress_, limit_);
    }

    // Define the function to store the Ethereum burn transaction hash and transfer native tokens (FTN)
    function processBurnTransaction(bytes32 burnTxHash_, address recipient_, uint256 amount_) external {

        require(initialized, 'Contract has not been initialized');
        require(amount_ <= limits[msg.sender], 'Limit exceeded');
        limits[msg.sender] -= amount_;
        _processBurnTransaction(burnTxHash_, recipient_, amount_);
    }

    function _processBurnTransaction(bytes32 burnTxHash_, address recipient_, uint256 amount_) private {

        require(! burnTransactionHashes[burnTxHash_], 'This burn transaction hash is already used');
        require(recipient_ != address(0), 'Invalid recipient address');

        burnTransactionHashes[burnTxHash_] = true;

        (bool success, ) = recipient_.call{value: amount_}('');
        require(success, 'Native token transfer failed');

        emit BurnTransactionProcessed(burnTxHash_, recipient_, amount_);
    }
}
