// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRentalEngine {
    function registerLease(address lessor, address lessee, uint256 tokenId, uint256 duration) external;
    function forceEndLease(uint256 tokenId) external;
}

contract LeaseAgreement is Ownable {
    IERC721 public immutable nft;
    IRentalEngine public rentalEngine;

    event LeaseStarted(address indexed lessor, address indexed lessee, uint256 tokenId, uint256 duration);
    event LeaseEnded(uint256 indexed tokenId, address endedBy);

    constructor(address _nft, address _rentalEngine) {
        nft = IERC721(_nft);
        rentalEngine = IRentalEngine(_rentalEngine);
    }

    function startLease(uint256 tokenId, address lessee, uint256 duration) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(duration >= 1 days, "Min duration is 1 day");

        // Transfer to engine, not to lessee directly
        nft.transferFrom(msg.sender, address(rentalEngine), tokenId);

        rentalEngine.registerLease(msg.sender, lessee, tokenId, duration);

        emit LeaseStarted(msg.sender, lessee, tokenId, duration);
    }

    function endLease(uint256 tokenId) external {
        rentalEngine.forceEndLease(tokenId);
        emit LeaseEnded(tokenId, msg.sender);
    }

    function updateEngine(address newEngine) external onlyOwner {
        rentalEngine = IRentalEngine(newEngine);
    }
}
