// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AuctionModule is Ownable {
    struct Auction {
        address seller;
        uint256 minBid;
        uint256 endTime;
        address highestBidder;
        uint256 highestBid;
        bool active;
    }

    IERC721 public nft;
    IERC20 public paymentToken;

    mapping(uint256 => Auction) public auctions;

    event AuctionStarted(uint256 tokenId, uint256 minBid, uint256 endTime);
    event BidPlaced(uint256 tokenId, address bidder, uint256 amount);
    event AuctionEnded(uint256 tokenId, address winner, uint256 amount);

    constructor(address _nft, address _token) {
        nft = IERC721(_nft);
        paymentToken = IERC20(_token);
    }

    function startAuction(uint256 tokenId, uint256 minBid, uint256 duration) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(duration >= 1 hours, "Too short");

        nft.transferFrom(msg.sender, address(this), tokenId);
        auctions[tokenId] = Auction({
            seller: msg.sender,
            minBid: minBid,
            endTime: block.timestamp + duration,
            highestBidder: address(0),
            highestBid: 0,
            active: true
        });

        emit AuctionStarted(tokenId, minBid, block.timestamp + duration);
    }

    function placeBid(uint256 tokenId, uint256 amount) external {
        Auction storage auction = auctions[tokenId];
        require(auction.active, "Not active");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(amount > auction.highestBid && amount >= auction.minBid, "Low bid");

        if (auction.highestBid > 0) {
            paymentToken.transfer(auction.highestBidder, auction.highestBid);
        }

        paymentToken.transferFrom(msg.sender, address(this), amount);
        auction.highestBid = amount;
        auction.highestBidder = msg.sender;

        emit BidPlaced(tokenId, msg.sender, amount);
    }

    function finalizeAuction(uint256 tokenId) external {
        Auction memory auction = auctions[tokenId];
        require(auction.active, "Already finalized");
        require(block.timestamp >= auction.endTime, "Too early");

        auctions[tokenId].active = false;

        if (auction.highestBid > 0) {
            nft.transferFrom(address(this), auction.highestBidder, tokenId);
            paymentToken.transfer(auction.seller, auction.highestBid);
            emit AuctionEnded(tokenId, auction.highestBidder, auction.highestBid);
        } else {
            nft.transferFrom(address(this), auction.seller, tokenId);
        }
    }
}
