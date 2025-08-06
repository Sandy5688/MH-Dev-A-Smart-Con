// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RentalEngine is Ownable {
    IERC721 public nft;
    address public treasury;

    struct Lease {
        address lessor;
        address lessee;
        uint256 expiresAt;
        bool active;
    }

    mapping(uint256 => Lease) public leases;

    event Rented(uint256 indexed tokenId, address indexed lessee, uint256 duration);
    event Returned(uint256 indexed tokenId, address indexed lessee);
    event Defaulted(uint256 indexed tokenId);

    constructor(address _nft) {
        nft = IERC721(_nft);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    function registerLease(address lessor, address lessee, uint256 tokenId, uint256 duration) external onlyOwner {
        require(!leases[tokenId].active, "Lease already active");

        leases[tokenId] = Lease({
            lessor: lessor,
            lessee: lessee,
            expiresAt: block.timestamp + duration,
            active: true
        });

        // Transfer to lessee for use (could restrict via wrapper)
        nft.transferFrom(address(this), lessee, tokenId);

        emit Rented(tokenId, lessee, duration);
    }

    function returnNFT(uint256 tokenId) external {
        Lease memory lease = leases[tokenId];
        require(lease.active, "Not leased");
        require(msg.sender == lease.lessee, "Only lessee can return");

        // End lease and return NFT to owner
        delete leases[tokenId];
        nft.transferFrom(msg.sender, lease.lessor, tokenId);

        emit Returned(tokenId, msg.sender);
    }

    function markDefaulted(uint256 tokenId) external onlyOwner {
        Lease memory lease = leases[tokenId];
        require(lease.active, "Lease not active");
        require(block.timestamp > lease.expiresAt, "Lease not expired");

        delete leases[tokenId];
        nft.transferFrom(lease.lessee, lease.lessor, tokenId);

        emit Defaulted(tokenId);
    }

    function forceEndLease(uint256 tokenId) external onlyOwner {
        Lease memory lease = leases[tokenId];
        if (lease.active) {
            delete leases[tokenId];
            nft.transferFrom(lease.lessee, lease.lessor, tokenId);
            emit Returned(tokenId, lease.lessee);
        }
    }

    function getLeaseInfo(uint256 tokenId) external view returns (Lease memory) {
        return leases[tokenId];
    }
}
