// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract EscrowManager is Ownable, IERC721Receiver {
    IERC721 public nftContract;
    mapping(address => bool) public trustedModules;

    struct Escrow {
        address depositor;
        uint256 tokenId;
        bool locked;
    }

    mapping(uint256 => Escrow) public escrows;

    event EscrowLocked(address indexed depositor, uint256 indexed tokenId);
    event EscrowReleased(address indexed recipient, uint256 indexed tokenId);
    event EscrowForfeited(address indexed to, uint256 indexed tokenId);
    event TrustedModuleUpdated(address indexed module, bool trusted);

    modifier onlyTrusted() {
        require(trustedModules[msg.sender], "Escrow: caller not trusted");
        _;
    }

    constructor(address _nft) {
        require(_nft != address(0), "Invalid NFT address");
        nftContract = IERC721(_nft);
    }

    function setTrusted(address module, bool trusted) external onlyOwner {
        trustedModules[module] = trusted;
        emit TrustedModuleUpdated(module, trusted);
    }

    /**
     * @notice Lock an NFT into escrow. The depositor MUST have approved this contract for tokenId.
     * @dev Prevents double-lock. Pulls token via safeTransferFrom so custody is consistent.
     */
    function lockAsset(uint256 tokenId, address depositor) external onlyTrusted {
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
     * @notice Release an NFT from escrow to recipient. Callable only by trusted modules.
     */
    function releaseAsset(uint256 tokenId, address recipient) external onlyTrusted {
        require(escrows[tokenId].locked, "Escrow: not locked");
        require(recipient != address(0), "Escrow: invalid recipient");

        // Remove from mapping before external call to avoid reentrancy issues
        delete escrows[tokenId];

        // Transfer NFT from escrow to recipient
        nftContract.safeTransferFrom(address(this), recipient, tokenId);

        emit EscrowReleased(recipient, tokenId);
    }

    /**
     * @notice Forfeit an escrowed NFT to a specified address (treasury/admin).
     * @dev Callable by trusted modules only. Transfers token out of escrow to `to`.
     */
    function forfeitAsset(uint256 tokenId, address to) external onlyTrusted {
        require(escrows[tokenId].locked, "Escrow: not locked");
        require(to != address(0), "Escrow: invalid recipient");

        delete escrows[tokenId];

        // Transfer NFT to designated address
        nftContract.safeTransferFrom(address(this), to, tokenId);

        emit EscrowForfeited(to, tokenId);
    }

    function isLocked(uint256 tokenId) external view returns (bool) {
        return escrows[tokenId].locked;
    }

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
