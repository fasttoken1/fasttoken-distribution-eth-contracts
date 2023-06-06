// ┏━━━┓━┏┓━━━━━━━━━┏━━━┓━━━━━━━━━━━━━━━━━━━┏┓━━━━━┏━━━┓━━━━━━━━━┏┓━━━━━━━━━━━━━━┏┓━
// ┃┏━━┛┏┛┗┓━━━━━━━━┗┓┏┓┃━━━━━━━━━━━━━━━━━━┏┛┗┓━━━━┃┏━┓┃━━━━━━━━┏┛┗┓━━━━━━━━━━━━┏┛┗┓
// ┃┗━━┓┗┓┏┛┏━┓━━━━━━┃┃┃┃┏━━┓┏━━┓┏━━┓┏━━┓┏┓┗┓┏┛━━━━┃┃━┗┛┏━━┓┏━┓━┗┓┏┛┏━┓┏━━┓━┏━━┓┗┓┏┛
// ┃┏━━┛━┃┃━┃┏┓┓━━━━━┃┃┃┃┃┏┓┃┃┏┓┃┃┏┓┃┃━━┫┣┫━┃┃━━━━━┃┃━┏┓┃┏┓┃┃┏┓┓━┃┃━┃┏┛┗━┓┃━┃┏━┛━┃┃━
// ┃┃━━━━┃┗┓┃┃┃┃━━━━┏┛┗┛┃┃┃━┫┃┗┛┃┃┗┛┃┣━━┃┃┃━┃┗┓━━━━┃┗━┛┃┃┗┛┃┃┃┃┃━┃┗┓┃┃━┃┗┛┗┓┃┗━┓━┃┗┓
// ┗┛━━━━┗━┛┗┛┗┛━━━━┗━━━┛┗━━┛┃┏━┛┗━━┛┗━━┛┗┛━┗━┛━━━━┗━━━┛┗━━┛┗┛┗┛━┗━┛┗┛━┗━━━┛┗━━┛━┗━┛
// ━━━━━━━━━━━━━━━━━━━━━━━━━━┃┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ━━━━━━━━━━━━━━━━━━━━━━━━━━┗┛━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.17;


// Based on official specification in https://eips.ethereum.org/EIPS/eip-165
interface ERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceId` and `interfaceId` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}

/// @notice This is the FastexChain(Bahamut) deposit contract interface.
interface IDepositContract {

    /// @notice A processed deposit event.
    event DepositEvent(
        bytes pubkey,
        bytes withdrawal_credentials,
        bytes contract_address,
        bytes amount,
        bytes signature,
        bytes index
    );

    /** 
     *  @notice Submit a DepositData object.
     *  @param pubkey A BLS12-381 public key.
     *  @param withdrawal_credentials Commitment to a public key for withdrawals.
     *  @param contract_address Address of the smart contract that a associated with this deposit.
     *  @param signature A BLS12-381 signature.
     *  @param deposit_data_root The SHA-256 hash of the SSZ-encoded DepositData object.
     */
    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata contract_address,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external payable;

    /** 
     *  @notice Changes contract ownership
     *  @param contract_address Address of the smart contract which ownership need to transfer
     *  @param new_owner_address New owner address
     */
    function transfer_contract_ownership(address contract_address, address new_owner_address) external;

    /**
     * @notice Query the owner of the given contract
     * @return The owner of the contract
     */
    function get_contract_owner(address contract_address) external view returns (address);

    /**
     * @notice Query the current deposit root hash.
     * @return The deposit root hash.
     */
    function get_deposit_root() external view returns (bytes32);

    /**
     * @notice Query the current deposit count.
     * @return The deposit count encoded as a little endian 64-bit number.
     */
    function get_deposit_count() external view returns (bytes memory);
}

/// @notice This is the FastexChain(Bahamut) deposit contract interface.
contract DepositContract is IDepositContract, ERC165 {

    uint256 private constant DEPOSIT_CONTRACT_TREE_DEPTH = 32;
    // NOTE: this also ensures `deposit_count` will fit into 64-bits
    uint256 private constant MAX_DEPOSIT_COUNT = 2**DEPOSIT_CONTRACT_TREE_DEPTH - 1;

    bytes32[DEPOSIT_CONTRACT_TREE_DEPTH] private branch;
    uint256 private deposit_count;

    bytes32[DEPOSIT_CONTRACT_TREE_DEPTH] private zero_hashes;

    address private deployer_getter = 0x1000000000000000000000000000000000000002;
    mapping (address => address) private contract_owners;

    constructor() {
        // Compute hashes in empty sparse Merkle tree
        for (uint256 height = 0; height < DEPOSIT_CONTRACT_TREE_DEPTH - 1; height++) {
            zero_hashes[height + 1] = sha256(abi.encodePacked(zero_hashes[height], zero_hashes[height]));
        }
    }

    function get_deposit_root() override external view returns (bytes32) {
        bytes32 node;
        uint256 size = deposit_count;
        for (uint256 height = 0; height < DEPOSIT_CONTRACT_TREE_DEPTH; height++) {
            if ((size & 1) == 1)
                node = sha256(abi.encodePacked(branch[height], node));
            else
                node = sha256(abi.encodePacked(node, zero_hashes[height]));
            size /= 2;
        }
        return sha256(abi.encodePacked(
            node,
            _to_little_endian_64(uint64(deposit_count)),
            bytes24(0)
        ));
    }

    function get_deposit_count() override external view returns (bytes memory) {
        return _to_little_endian_64(uint64(deposit_count));
    }

    function transfer_contract_ownership(address contract_address, address new_owner_address) external {

        require(address(0x0) != contract_address, 'DepositContract: Contract address cannot be null');
        require(address(0x0) != new_owner_address, 'DepositContract: Owner address cannot be null');
        require(msg.sender == get_contract_owner(contract_address), 'DepositContract: Only owner can transfer ownership');
        contract_owners[contract_address] = new_owner_address;
    }

    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata contract_address,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) override external payable {

        // Extended ABI length checks since dynamic types are used.
        require(pubkey.length == 48, "DepositContract: invalid pubkey length");
        require(withdrawal_credentials.length == 32, "DepositContract: invalid withdrawal_credentials length");
        require(contract_address.length == 20, "DepositContract: invalid withdrawal_credentials length");
        require(signature.length == 96, "DepositContract: invalid signature length");

        // Check deposit amount
        address c_address = _to_address(contract_address);
        if (address(0x0) != c_address) {
            require(get_contract_owner(c_address) == msg.sender, "DepositContract: sender should be owner of contract");
        }
        require(msg.value >= 256 ether, "DepositContract: deposit value too low");
        require(msg.value % 1 gwei == 0, "DepositContract: deposit value not multiple of gwei");
        uint256 deposit_amount = msg.value / 1 gwei;
        require(deposit_amount <= type(uint64).max, "DepositContract: deposit value too high");

        // Emit `DepositEvent` log
        bytes memory amount = _to_little_endian_64(uint64(deposit_amount));
        emit DepositEvent(
            pubkey,
            withdrawal_credentials,
            contract_address,
            amount,
            signature,
            _to_little_endian_64(uint64(deposit_count))
        );

        // Compute deposit data root (`DepositData` hash tree root)
        bytes32 root = _calculate_root(
            pubkey,
            withdrawal_credentials,
            contract_address,
            amount,
            signature);

        // Verify computed and expected deposit data roots match
        require(root == deposit_data_root, "DepositContract: reconstructed DepositData does not match supplied deposit_data_root");

        // Avoid overflowing the Merkle tree (and prevent edge case in computing `branch`)
        require(deposit_count < MAX_DEPOSIT_COUNT, "DepositContract: merkle tree full");

        // Add deposit data root to Merkle tree (update a single `branch` node)
        deposit_count += 1;

        _update_branch(root);
    }

    function supportsInterface(bytes4 interfaceId) override external pure returns (bool) {
        return interfaceId == type(ERC165).interfaceId || interfaceId == type(IDepositContract).interfaceId;
    }

    function get_contract_owner(address contract_address) public view returns (address) {

        if (address(0x0) != contract_owners[contract_address]) {
            return contract_owners[contract_address];
        }

        (bool success, bytes memory deployer) = deployer_getter.staticcall(abi.encodePacked(contract_address));
        /*
        (bool success, bytes memory deployer) = deployer_getter.staticcall(
            abi.encodeWithSignature("deployer(address)", contract_address));
        */
        require(success, 'DepositContract: Cannot get deployer');
        return _to_address(deployer);
    }

    /// Helper member functions

    function _to_address(bytes memory addr) private pure returns (address ret_address) {

        assembly {
            ret_address := mload(add(addr, 20))
        }
    }

    function _to_little_endian_64(uint64 value) private pure returns (bytes memory ret) {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }

    function _calculate_root(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata contract_address,
        bytes memory amount,
        bytes calldata signature)
            pure
            private
            returns(bytes32) {

        bytes32 pubkey_root = sha256(abi.encodePacked(pubkey, bytes16(0)));
        bytes32 signature_root = sha256(abi.encodePacked(
            sha256(abi.encodePacked(signature[:64])),
            sha256(abi.encodePacked(signature[64:], bytes32(0)))
        ));

        bytes32 node1 = sha256(abi.encodePacked(pubkey_root, withdrawal_credentials));
        bytes32 node2 = sha256(abi.encodePacked(contract_address, bytes12(0), amount, bytes24(0)));
        bytes32 node3 = sha256(abi.encodePacked(signature_root, bytes32(0)));
        bytes32 node4 = sha256(abi.encodePacked(bytes32(0), bytes32(0)));

        bytes32 node12 = sha256(abi.encodePacked(node1, node2));
        bytes32 node34 = sha256(abi.encodePacked(node3, node4));

        return sha256(abi.encodePacked(node12, node34));
    }

    function _update_branch(bytes32 root) private {

        uint256 size = deposit_count;
        for (uint256 height = 0; height < DEPOSIT_CONTRACT_TREE_DEPTH; height++) {
            if ((size & 1) == 1) {
                branch[height] = root;
                return;
            }
            root = sha256(abi.encodePacked(branch[height], root));
            size /= 2;
        }
        // As the loop should always end prematurely with the `return` statement,
        // this code should be unreachable. We assert `false` just to be safe.
        assert(false);
    }
}
