// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract EscrowManager is Ownable {
    IERC721 public nftContract;
    mapping(address => bool) public trustedModules;

    struct Escrow {
        address depositor;
        uint256 tokenId;
        bool locked;
    }

    mapping(uint256 => Escrow) public escrows;

    event EscrowLocked(address indexed by, uint256 tokenId);
    event EscrowReleased(address indexed to, uint256 tokenId);
    event EscrowForfeited(uint256 tokenId);

    modifier onlyTrusted() {
        require(trustedModules[msg.sender], "Not trusted");
        _;
    }

    constructor(address _nft) {
        nftContract = IERC721(_nft);
    }
    function setTrusted(address module, bool trusted) external onlyOwner {
        trustedModules[module] = trusted;
    }

    function lockAsset(uint256 tokenId, address depositor) external onlyTrusted {
        nftContract.transferFrom(depositor, address(this), tokenId);
        escrows[tokenId] = Escrow(depositor, tokenId, true);
        emit EscrowLocked(depositor, tokenId);
    }

    function releaseAsset(uint256 tokenId, address recipient) external onlyTrusted {
        require(escrows[tokenId].locked, "Not locked");
        delete escrows[tokenId];
        nftContract.transferFrom(address(this), recipient, tokenId);
        emit EscrowReleased(recipient, tokenId);
    }

    function forfeitAsset(uint256 tokenId) external onlyTrusted {
        require(escrows[tokenId].locked, "Not locked");
        delete escrows[tokenId];
        emit EscrowForfeited(tokenId);
        // Token remains in contract or burned by admin separately
    }

    function isLocked(uint256 tokenId) external view returns (bool) {
        return escrows[tokenId].locked;
    }
}
