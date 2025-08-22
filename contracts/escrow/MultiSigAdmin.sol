--- a/MultiSigAdmin.sol
+++ b/MultiSigAdmin.sol
@@ -1,10 +1,17 @@
 // SPDX-License-Identifier: MIT 
-pragma solidity ^0.8.28;
+pragma solidity ^0.8.20;

 import "@openzeppelin/contracts/utils/Address.sol";

 contract MultiSigAdmin {
     using Address for address;

     address[3] public signers;
+    uint256 public constant THRESHOLD = 2; // 2-of-3
     uint256 public txCount;

     struct Transaction {
         address to;
         uint256 value;
         bytes data;
         uint256 confirmations;
         bool executed;
     }
@@
     event TxSubmitted(uint256 txId, address indexed to, uint256 value);
     event Confirmed(uint256 txId, address indexed by);
     event Revoked(uint256 txId, address indexed by);
     event Executed(uint256 txId);
-    event SignerReplaced(address indexed oldSigner, address indexed newSigner);
+    event SignerReplaced(address indexed oldSigner, address indexed newSigner);
+    event SignerReplaceProposed(uint256 txId, address indexed oldSigner, address indexed newSigner);

     modifier onlySigner() {
         require(isSigner(msg.sender), "Not authorized");
         _;
     }

     constructor(address[3] memory _signers) {
         for (uint256 i = 0; i < 3; i++) {
             require(_signers[i] != address(0), "Invalid signer");
+            // ensure uniqueness
+            for (uint256 j = 0; j < i; j++) {
+                require(_signers[i] != _signers[j], "Duplicate signer");
+            }
         }
         signers = _signers;
     }
@@
     function submitTx(address to, uint256 value, bytes calldata data) external onlySigner returns (uint256) {
         require(to != address(0), "Invalid target");
+        // If sending ETH, ensure this contract has balance
+        if (value > 0) require(address(this).balance >= value, "Insufficient multisig balance");
         uint256 txId = txCount++;
         transactions[txId] = Transaction(to, value, data, 0, false);
         emit TxSubmitted(txId, to, value);
         confirmTx(txId);
         return txId;
     }
@@
         emit Confirmed(txId, msg.sender);

-        // Execute if at least 2-of-3 confirm
-        if (txn.confirmations >= 2) {
+        // Execute if at least threshold confirm
+        if (txn.confirmations >= THRESHOLD) {
             _executeTx(txId);
         }
     }
@@
     function _executeTx(uint256 txId) internal {
         Transaction storage txn = transactions[txId];
         require(!txn.executed, "Already executed");

         txn.executed = true;

         // Safer external call using OZ Address.functionCallWithValue
         txn.to.functionCallWithValue(txn.data, txn.value);

         emit Executed(txId);
     }
-
-    function replaceSigner(address oldSigner, address newSigner) external onlySigner {
-        require(newSigner != address(0), "Invalid new signer");
-        bool replaced = false;
-        for (uint256 i = 0; i < 3; i++) {
-            if (signers[i] == oldSigner) {
-                signers[i] = newSigner;
-                replaced = true;
-                break;
-            }
-        }
-        require(replaced, "Old signer not found");
-        emit SignerReplaced(oldSigner, newSigner);
-    }
+
+    /**
+     * @dev Signer replacement MUST go through the same multisig flow.
+     * Create a tx with `to = address(this)` and `data = abi.encodeWithSignature("replaceSignerViaTx(address,address)", oldSigner, newSigner)`
+     */
+    function replaceSignerViaTx(address oldSigner, address newSigner) external {
+        require(msg.sender == address(this), "Use multisig tx");
+        require(newSigner != address(0), "Invalid new signer");
+        require(oldSigner != address(0), "Invalid old signer");
+        require(!isSigner(newSigner), "Already a signer");
+        bool replaced = false;
+        for (uint256 i = 0; i < 3; i++) {
+            if (signers[i] == oldSigner) {
+                signers[i] = newSigner;
+                replaced = true;
+                break;
+            }
+        }
+        require(replaced, "Old signer not found");
+        emit SignerReplaced(oldSigner, newSigner);
+    }
+
+    // Helper to propose a signer change via submitTx UX
+    function proposeReplaceSigner(address oldSigner, address newSigner) external onlySigner returns (uint256 txId) {
+        bytes memory data = abi.encodeWithSignature("replaceSignerViaTx(address,address)", oldSigner, newSigner);
+        txId = submitTx(address(this), 0, data);
+        emit SignerReplaceProposed(txId, oldSigner, newSigner);
+    }

     receive() external payable {}
 }
