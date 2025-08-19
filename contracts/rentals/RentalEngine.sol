// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Rental engine to manage NFT leases with custody
contract RentalEngine is Ownable, ERC721Holder, ReentrancyGuard {
    IERC721 public nft;
    address public treasury;
    uint256 public maxRentalPeriod = 30 days;

    /// @notice Trusted modules (e.g., LeaseAgreement) allowed to call registerLease
    mapping(address => bool) public trustedModules;

    struct Lease {
        address lessor;
        address lessee;
        uint256 expiresAt;
        bool active;
    }

    mapping(uint256 => Lease) public leases;

    event LeaseStarted(uint256 indexed tokenId, address indexed lessee, uint256 duration);
    event LeaseEnded(uint256 indexed tokenId, address indexed lessee);
    event LeaseDefaulted(uint256 indexed tokenId);
    event TrustedModuleUpdated(address indexed module, bool enabled);

    constructor(address _nft) {
        require(_nft != address(0), "Invalid NFT address");
        nft = IERC721(_nft);
    }

    /// @notice Owner can set the treasury
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    /// @notice Owner can update trusted modules
    function setTrustedModule(address module, bool enabled) external onlyOwner {
        require(module != address(0), "Invalid module");
        trustedModules[module] = enabled;
        emit TrustedModuleUpdated(module, enabled);
    }

    /// @notice Register a lease (only trusted modules)
    function registerLease(
        address lessor,
        address lessee,
        uint256 tokenId,
        uint256 duration
    ) external nonReentrant {
        require(trustedModules[msg.sender], "Caller not trusted");
        require(!leases[tokenId].active, "Lease already active");
        require(duration > 0 && duration <= maxRentalPeriod, "Invalid duration");

        // Pull NFT into custody using safe transfer
        nft.safeTransferFrom(lessor, address(this), tokenId);

        leases[tokenId] = Lease({
            lessor: lessor,
            lessee: lessee,
            expiresAt: block.timestamp + duration,
            active: true
        });

        emit LeaseStarted(tokenId, lessee, duration);
    }

    /// @notice Lessee returns NFT early
    function returnNFT(uint256 tokenId) external nonReentrant {
        Lease memory lease = leases[tokenId];
        require(lease.active, "Not leased");
        require(msg.sender == lease.lessee, "Only lessee can return");

        delete leases[tokenId];
        nft.safeTransferFrom(address(this), lease.lessor, tokenId);

        emit LeaseEnded(tokenId, msg.sender);
    }

    /// @notice Mark a lease defaulted (after expiry)
    function markDefaulted(uint256 tokenId) external nonReentrant onlyOwner {
        Lease memory lease = leases[tokenId];
        require(lease.active, "Lease not active");
        require(block.timestamp > lease.expiresAt, "Lease not expired");

        delete leases[tokenId];
        nft.safeTransferFrom(address(this), lease.lessor, tokenId);

        emit LeaseDefaulted(tokenId);
    }

    /// @notice Force end lease (emergency)
    function forceEndLease(uint256 tokenId) external nonReentrant onlyOwner {
        Lease memory lease = leases[tokenId];
        require(lease.active, "Not leased");
        
        delete leases[tokenId];
        nft.safeTransferFrom(address(this), lease.lessor, tokenId);
        
        emit LeaseEnded(tokenId, lease.lessee);
    }

    /// @notice Get lessor of an NFT
    function getLessor(uint256 tokenId) external view returns (address) {
        require(leases[tokenId].active, "Not leased");
        return leases[tokenId].lessor;
    }

    /// @notice End lease and return NFT to lessor (only trusted modules or on expiry)
    function endLease(uint256 tokenId) external nonReentrant {
        Lease memory lease = leases[tokenId];
        require(lease.active, "Not leased");
        
        // Allow trusted modules to end lease anytime
        bool isTrustedModule = trustedModules[msg.sender];
        if (!isTrustedModule) {
            // Direct calls only allowed by lessor after expiry
            require(msg.sender == lease.lessor, "Only lessor can end lease");
            require(block.timestamp > lease.expiresAt, "Lease not expired");
        }
        
        delete leases[tokenId];
        nft.safeTransferFrom(address(this), lease.lessor, tokenId);
        emit LeaseEnded(tokenId, lease.lessee);
    }

    /// @notice Returns info about a lease
    function getLeaseInfo(uint256 tokenId) external view returns (Lease memory) {
        return leases[tokenId];
    }
}
