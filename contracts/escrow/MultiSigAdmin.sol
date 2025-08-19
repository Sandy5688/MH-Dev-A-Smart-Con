// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Address.sol";

contract MultiSigAdmin {
    using Address for address;

    address[3] public signers;
    uint256 public txCount;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        uint256 confirmations;
        bool executed;
    }

    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => mapping(address => bool)) public isConfirmed;

    event TxSubmitted(uint256 txId, address indexed to, uint256 value);
    event Confirmed(uint256 txId, address indexed by);
    event Revoked(uint256 txId, address indexed by);
    event Executed(uint256 txId);
    event SignerReplaced(address indexed oldSigner, address indexed newSigner);

    modifier onlySigner() {
        require(isSigner(msg.sender), "Not authorized");
        _;
    }

    constructor(address[3] memory _signers) {
        for (uint256 i = 0; i < 3; i++) {
            require(_signers[i] != address(0), "Invalid signer");
        }
        signers = _signers;
    }

    function isSigner(address addr) public view returns (bool) {
        return (addr == signers[0] || addr == signers[1] || addr == signers[2]);
    }

    function submitTx(address to, uint256 value, bytes calldata data) external onlySigner returns (uint256) {
        require(to != address(0), "Invalid target");
        uint256 txId = txCount++;
        transactions[txId] = Transaction(to, value, data, 0, false);
        emit TxSubmitted(txId, to, value);
        confirmTx(txId);
        return txId;
    }

    function confirmTx(uint256 txId) public onlySigner {
        Transaction storage txn = transactions[txId];
        require(!txn.executed, "Already executed");
        require(!isConfirmed[txId][msg.sender], "Already confirmed");

        isConfirmed[txId][msg.sender] = true;
        txn.confirmations += 1;

        emit Confirmed(txId, msg.sender);

        // Execute if at least 2-of-3 confirm
        if (txn.confirmations >= 2) {
            _executeTx(txId);
        }
    }

    function revokeConfirmation(uint256 txId) external onlySigner {
        Transaction storage txn = transactions[txId];
        require(!txn.executed, "Already executed");
        require(isConfirmed[txId][msg.sender], "Not confirmed");

        isConfirmed[txId][msg.sender] = false;
        txn.confirmations -= 1;

        emit Revoked(txId, msg.sender);
    }

    function _executeTx(uint256 txId) internal {
        Transaction storage txn = transactions[txId];
        require(!txn.executed, "Already executed");

        txn.executed = true;

        // Safer external call using OZ Address.functionCallWithValue
        txn.to.functionCallWithValue(txn.data, txn.value);

        emit Executed(txId);
    }

    function replaceSigner(address oldSigner, address newSigner) external onlySigner {
        require(newSigner != address(0), "Invalid new signer");
        bool replaced = false;
        for (uint256 i = 0; i < 3; i++) {
            if (signers[i] == oldSigner) {
                signers[i] = newSigner;
                replaced = true;
                break;
            }
        }
        require(replaced, "Old signer not found");
        emit SignerReplaced(oldSigner, newSigner);
    }

    receive() external payable {}
}
