--- a/EscrowManager.sol
+++ b/EscrowManager.sol
@@ -1,19 +1,34 @@
 // SPDX-License-Identifier: MIT
-pragma solidity ^0.8.20;
+pragma solidity ^0.8.20;

 import "@openzeppelin/contracts/access/Ownable.sol";
 import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
 import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
+import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
+import "@openzeppelin/contracts/security/Pausable.sol";

-contract EscrowManager is Ownable, IERC721Receiver {
+contract EscrowManager is Ownable, IERC721Receiver, ReentrancyGuard, Pausable {
     IERC721 public nftContract;
     mapping(address => bool) public trustedModules;
+    address public multisig; // ONLY this can release/forfeit

     struct Escrow {
         address depositor;
         uint256 tokenId;
         bool locked;
     }

     mapping(uint256 => Escrow) public escrows;

     event EscrowLocked(address indexed depositor, uint256 indexed tokenId);
-    event EscrowReleased(address indexed recipient, uint256 indexed tokenId);
-    event EscrowForfeited(address indexed to, uint256 indexed tokenId);
+    event EscrowReleased(address indexed recipient, uint256 indexed tokenId);
+    event EscrowForfeited(address indexed to, uint256 indexed tokenId);
     event TrustedModuleUpdated(address indexed module, bool trusted);
+    event MultisigUpdated(address indexed newMultisig);
+    event EmergencyWithdraw(address indexed to, uint256 indexed tokenId);

     modifier onlyTrusted() {
         require(trustedModules[msg.sender], "Escrow: caller not trusted");
         _;
     }
+
+    modifier onlyMultisig() {
+        require(msg.sender == multisig, "Escrow: only multisig");
+        _;
+    }

-    constructor(address _nft) {
+    constructor(address _nft, address _multisig) {
         require(_nft != address(0), "Invalid NFT address");
+        require(_multisig != address(0), "Invalid multisig");
         nftContract = IERC721(_nft);
+        multisig = _multisig;
+        emit MultisigUpdated(_multisig);
     }

     function setTrusted(address module, bool trusted) external onlyOwner {
         trustedModules[module] = trusted;
         emit TrustedModuleUpdated(module, trusted);
     }
+
+    function setMultisig(address _multisig) external onlyOwner {
+        require(_multisig != address(0), "Invalid multisig");
+        multisig = _multisig;
+        emit MultisigUpdated(_multisig);
+    }
+
+    function pause() external onlyOwner { _pause(); }
+    function unpause() external onlyOwner { _unpause(); }

     /**
      * @notice Lock an NFT into escrow. The depositor MUST have approved this contract for tokenId.
      * @dev Prevents double-lock. Pulls token via safeTransferFrom so custody is consistent.
      */
-    function lockAsset(uint256 tokenId, address depositor) external onlyTrusted {
+    function lockAsset(uint256 tokenId, address depositor) external onlyTrusted whenNotPaused nonReentrant {
         require(!escrows[tokenId].locked, "Escrow: already locked");
         require(depositor != address(0), "Escrow: invalid depositor");
         require(nftContract.ownerOf(tokenId) == depositor, "Escrow: depositor not owner");

         // Pull the NFT into escrow
         nftContract.safeTransferFrom(depositor, address(this), tokenId);

         escrows[tokenId] = Escrow({
             depositor: depositor,
             tokenId: tokenId,
             locked: true
         });

         emit EscrowLocked(depositor, tokenId);
     }

     /**
-     * @notice Release an NFT from escrow to recipient. Callable only by trusted modules.
+     * @notice Release an NFT from escrow to recipient. Callable ONLY by multisig (2-of-3).
      */
-    function releaseAsset(uint256 tokenId, address recipient) external onlyTrusted {
+    function releaseAsset(uint256 tokenId, address recipient) external onlyMultisig whenNotPaused nonReentrant {
         require(escrows[tokenId].locked, "Escrow: not locked");
         require(recipient != address(0), "Escrow: invalid recipient");

         // Remove from mapping before external call to avoid reentrancy issues
         delete escrows[tokenId];

         // Transfer NFT from escrow to recipient
         nftContract.safeTransferFrom(address(this), recipient, tokenId);

         emit EscrowReleased(recipient, tokenId);
     }

     /**
-     * @notice Forfeit an escrowed NFT to a specified address (treasury/admin).
-     * @dev Callable by trusted modules only. Transfers token out of escrow to `to`.
+     * @notice Forfeit an escrowed NFT to a specified address (treasury/admin).
+     * @dev Callable ONLY by multisig.
      */
-    function forfeitAsset(uint256 tokenId, address to) external onlyTrusted {
+    function forfeitAsset(uint256 tokenId, address to) external onlyMultisig whenNotPaused nonReentrant {
         require(escrows[tokenId].locked, "Escrow: not locked");
         require(to != address(0), "Escrow: invalid recipient");

         delete escrows[tokenId];

         // Transfer NFT to designated address
         nftContract.safeTransferFrom(address(this), to, tokenId);

         emit EscrowForfeited(to, tokenId);
     }
@@
     function isLocked(uint256 tokenId) external view returns (bool) {
         return escrows[tokenId].locked;
     }
@@
     function getEscrow(uint256 tokenId) external view returns (address depositor, uint256 id, bool locked) {
         Escrow memory e = escrows[tokenId];
         return (e.depositor, e.tokenId, e.locked);
     }
+
+    /**
+     * @notice Emergency escape hatch: owner can withdraw an NFT stuck in contract (only when paused).
+     * @dev This is for exceptional recovery. NFT is returned to recorded depositor by default.
+     */
+    function emergencyWithdraw(uint256 tokenId, address to) external onlyOwner whenPaused {
+        address recipient = to == address(0) ? escrows[tokenId].depositor : to;
+        require(recipient != address(0), "Escrow: bad emergency recipient");
+        delete escrows[tokenId];
+        nftContract.safeTransferFrom(address(this), recipient, tokenId);
+        emit EmergencyWithdraw(recipient, tokenId);
+    }

     /**
      * @notice ERC721 receiver handler so safeTransferFrom to this contract succeeds.
      */
     function onERC721Received(
         address /*operator*/,
         address /*from*/,
         uint256 /*tokenId*/,
         bytes calldata /*data*/
     ) external pure override returns (bytes4) {
         return IERC721Receiver.onERC721Received.selector;
     }
 }
