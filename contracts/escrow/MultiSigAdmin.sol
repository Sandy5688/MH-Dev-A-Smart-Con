// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MultiSigAdmin {
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

    event TxSubmitted(uint256 txId, address to, uint256 value);
    event Confirmed(uint256 txId, address by);
    event Executed(uint256 txId);

    modifier onlySigner() {
        require(isSigner(msg.sender), "Not authorized");
        _;
    }

    constructor(address[3] memory _signers) {
        signers = _signers;
    }

    function isSigner(address addr) public view returns (bool) {
        return (addr == signers[0] || addr == signers[1] || addr == signers[2]);
    }

    function submitTx(address to, uint256 value, bytes calldata data) external onlySigner returns (uint256) {
        uint256 txId = txCount++;
        transactions[txId] = Transaction(to, value, data, 0, false);
        emit TxSubmitted(txId, to, value);
        confirmTx(txId);
        return txId;
    }

    function confirmTx(uint256 txId) public onlySigner {
        require(!transactions[txId].executed, "Already executed");
        require(!isConfirmed[txId][msg.sender], "Already confirmed");

        isConfirmed[txId][msg.sender] = true;
        transactions[txId].confirmations += 1;

        emit Confirmed(txId, msg.sender);

        if (transactions[txId].confirmations >= 2) {
            _executeTx(txId);
        }
    }

    function _executeTx(uint256 txId) internal {
        Transaction storage txn = transactions[txId];
        require(!txn.executed, "Already executed");

        txn.executed = true;
        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        require(success, "Tx failed");

        emit Executed(txId);
    }

    receive() external payable {}
}
