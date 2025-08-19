// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRentalEngine {
    function registerLease(address lessor, address lessee, uint256 tokenId, uint256 duration) external;
    function endLease(uint256 tokenId) external;
    function forceEndLease(uint256 tokenId) external;
    function getLessor(uint256 tokenId) external view returns (address);
}

contract LeaseAgreement is Ownable {
    IERC721 public immutable nft;
    IRentalEngine public rentalEngine;

    event LeaseStarted(address indexed lessor, address indexed lessee, uint256 tokenId, uint256 duration);
    event LeaseEnded(uint256 indexed tokenId, address endedBy);

    constructor(address _nft, address _rentalEngine) {
        require(_nft != address(0), "Invalid NFT address");
        require(_rentalEngine != address(0), "Invalid engine address");
        nft = IERC721(_nft);
        rentalEngine = IRentalEngine(_rentalEngine);
    }

    /// @notice Start a lease by transferring NFT to RentalEngine and registering lease
    function startLease(uint256 tokenId, address lessee, uint256 duration) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(duration >= 1 days, "Min duration is 1 day");

        // Call engine to register lease (engine will pull NFT)
        rentalEngine.registerLease(msg.sender, lessee, tokenId, duration);

        emit LeaseStarted(msg.sender, lessee, tokenId, duration);
    }

    /// @notice End a lease (termination by lessor)
    function endLease(uint256 tokenId) external {
        require(msg.sender == rentalEngine.getLessor(tokenId), "Not authorized");
        rentalEngine.endLease(tokenId);
        emit LeaseEnded(tokenId, msg.sender);
    }

    /// @notice Owner can update the RentalEngine address
    function updateEngine(address newEngine) external onlyOwner {
        require(newEngine != address(0), "Invalid engine address");
        rentalEngine = IRentalEngine(newEngine);
    }
}
