// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BiddingSystem is Ownable {
    struct Bid {
        address bidder;
        uint256 amount;
    }

    IERC721 public nft;
    IERC20 public token;

    mapping(uint256 => Bid[]) public bids;

    event BidPlaced(uint256 tokenId, address bidder, uint256 amount);
    event BidAccepted(uint256 tokenId, address winner, uint256 amount);
    event BidCancelled(uint256 tokenId, address bidder);

    constructor(address _nft, address _token) {
        nft = IERC721(_nft);
        token = IERC20(_token);
    }

    function placeBid(uint256 tokenId, uint256 amount) external {
        require(amount > 0, "Zero bid");
        token.transferFrom(msg.sender, address(this), amount);
        bids[tokenId].push(Bid(msg.sender, amount));

        emit BidPlaced(tokenId, msg.sender, amount);
    }

    function cancelBid(uint256 tokenId) external {
        Bid[] storage list = bids[tokenId];
        for (uint i = 0; i < list.length; i++) {
            if (list[i].bidder == msg.sender) {
                token.transfer(msg.sender, list[i].amount);
                list[i] = list[list.length - 1];
                list.pop();
                emit BidCancelled(tokenId, msg.sender);
                return;
            }
        }
        revert("No bid found");
    }

    function acceptBid(uint256 tokenId, uint256 index) external {
        Bid memory accepted = bids[tokenId][index];
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");

        nft.transferFrom(msg.sender, accepted.bidder, tokenId);
        token.transfer(msg.sender, accepted.amount);

        delete bids[tokenId];

        emit BidAccepted(tokenId, accepted.bidder, accepted.amount);
    }
}
