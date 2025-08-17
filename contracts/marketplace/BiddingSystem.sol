// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IEscrowManager {
    function lockAsset(uint256 tokenId, address depositor) external;
}

contract BiddingSystem is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }

    IERC721 public immutable nft;
    IERC20 public immutable paymentToken;
    IEscrowManager public immutable escrow;

    // tokenId => list of bids
    mapping(uint256 => Bid[]) private _bids;

    // tokenId => auto accept price
    mapping(uint256 => uint256) public autoAcceptPrice;

    event BidSubmitted(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event BidAccepted(uint256 indexed tokenId, address indexed winner, uint256 amount);
    event BidRejected(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event AutoAcceptPriceSet(uint256 indexed tokenId, uint256 price);

    constructor(address _nft, address _token, address _escrow) {
        require(_nft != address(0) && _token != address(0) && _escrow != address(0), "Invalid address");
        nft = IERC721(_nft);
        paymentToken = IERC20(_token);
        escrow = IEscrowManager(_escrow);
    }

    /* ----------------- Seller Config ----------------- */
    function setAutoAcceptPrice(uint256 tokenId, uint256 price) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");
        autoAcceptPrice[tokenId] = price;
        emit AutoAcceptPriceSet(tokenId, price);
    }

    /* ----------------- Bid Logic ----------------- */
    function placeBid(uint256 tokenId, uint256 amount) external nonReentrant {
        require(amount > 0, "Zero bid");

        // Ensure bid is higher than the current highest bid
        uint256 currentHighest = _highestBid(tokenId);
        require(amount > currentHighest, "Bid not higher than current");

        // Pull payment tokens from bidder
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        _bids[tokenId].push(Bid({
            bidder: msg.sender,
            amount: amount,
            timestamp: block.timestamp
        }));

        emit BidSubmitted(tokenId, msg.sender, amount);

        // Auto accept if meets threshold
        uint256 threshold = autoAcceptPrice[tokenId];
        if (threshold > 0 && amount >= threshold) {
            _acceptBidInternal(tokenId, _bids[tokenId].length - 1);
        }
    }

    function cancelBid(uint256 tokenId) external nonReentrant {
        Bid[] storage list = _bids[tokenId];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].bidder == msg.sender) {
                uint256 refund = list[i].amount;
                paymentToken.safeTransfer(msg.sender, refund);

                emit BidRejected(tokenId, msg.sender, refund);

                list[i] = list[list.length - 1];
                list.pop();
                return;
            }
        }
        revert("No bid found");
    }

    function acceptBid(uint256 tokenId, uint256 index) external nonReentrant {
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        _acceptBidInternal(tokenId, index);
    }

    function _acceptBidInternal(uint256 tokenId, uint256 index) internal {
        require(index < _bids[tokenId].length, "Invalid bid index");
        Bid memory accepted = _bids[tokenId][index];
        require(accepted.amount > 0, "Invalid bid");

        address seller = nft.ownerOf(tokenId);

    // Lock NFT into escrow (seller must have approved escrow beforehand)
    escrow.lockAsset(tokenId, seller);

        // Pay seller immediately
        paymentToken.safeTransfer(seller, accepted.amount);

        // Clear bids for tokenId
        delete _bids[tokenId];

        emit BidAccepted(tokenId, accepted.bidder, accepted.amount);
    }

    /* ----------------- View ----------------- */
    function getBids(uint256 tokenId) external view returns (Bid[] memory) {
        return _bids[tokenId];
    }

    function _highestBid(uint256 tokenId) internal view returns (uint256 highest) {
        Bid[] storage list = _bids[tokenId];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].amount > highest) {
                highest = list[i].amount;
            }
        }
    }
}
