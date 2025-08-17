// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IEscrowManager {
    function lockAsset(uint256 tokenId, address depositor) external;
    function releaseAsset(uint256 tokenId, address recipient) external;
    function forfeitAsset(uint256 tokenId, address to) external;
}

interface IRoyaltyManager {
    function distributeRoyaltyFromContract(uint256 tokenId, uint256 salePrice) external returns (uint256);
}

contract AuctionModule is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Auction {
        address seller;
        uint256 minBid;
        uint256 endTime;
        address highestBidder;
        uint256 highestBid;
        bool active;
    }

    IERC721 public immutable nft;
    IERC20 public immutable paymentToken;
    IEscrowManager public immutable escrow;
    IRoyaltyManager public royaltyManager;
    address public treasury;
    uint256 public platformFeeBps = 500; // 5%
    uint256 public constant BPS_DENOMINATOR = 10000;

    // tokenId => auction
    mapping(uint256 => Auction) public auctions;

    // bidder => amount available to withdraw (accumulates refunds across auctions)
    mapping(address => uint256) public pendingReturns;

    event AuctionCreated(uint256 indexed tokenId, address indexed seller, uint256 minBid, uint256 endTime);
    event BidPlaced(uint256 indexed tokenId, address indexed bidder, uint256 amount);
    event AuctionSettled(uint256 indexed tokenId, address indexed winner, uint256 amount, uint256 royaltyPaid, uint256 platformFee);
    event AuctionCancelled(uint256 indexed tokenId, address indexed seller);
    event Withdrawn(address indexed bidder, uint256 amount);

    constructor(
        address _nft,
        address _paymentToken,
        address _escrow,
        address _treasury,
        address _royaltyManager
    ) {
        require(_nft != address(0) && _paymentToken != address(0) && _escrow != address(0) && _treasury != address(0), "Invalid addresses");
        nft = IERC721(_nft);
        paymentToken = IERC20(_paymentToken);
        escrow = IEscrowManager(_escrow);
        treasury = _treasury;
        if (_royaltyManager != address(0)) {
            royaltyManager = IRoyaltyManager(_royaltyManager);
        }
    }

    /* ===================== Admin ===================== */

    function setRoyaltyManager(address _rm) external onlyOwner {
        royaltyManager = IRoyaltyManager(_rm);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    function setPlatformFee(uint256 bps) external onlyOwner {
        require(bps <= 1000, "Max 10%");
        platformFeeBps = bps;
    }

    /* ===================== Auction lifecycle ===================== */

    /// @notice Start an auction. Seller must approve EscrowManager to pull the NFT.
    function startAuction(uint256 tokenId, uint256 minBid, uint256 duration) external nonReentrant {
        require(duration >= 1 hours, "Duration too short");
        require(minBid > 0, "minBid > 0");
        require(!auctions[tokenId].active, "Auction exists");
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");

        // Lock NFT into escrow; escrow pulls NFT from seller (seller must have approved escrow)
        escrow.lockAsset(tokenId, msg.sender);

        auctions[tokenId] = Auction({
            seller: msg.sender,
            minBid: minBid,
            endTime: block.timestamp + duration,
            highestBidder: address(0),
            highestBid: 0,
            active: true
        });

        emit AuctionCreated(tokenId, msg.sender, minBid, block.timestamp + duration);
    }

    /// @notice Place a bid. Buyer must approve paymentToken to this contract for `amount`.
    function placeBid(uint256 tokenId, uint256 amount) external nonReentrant {
        Auction storage auc = auctions[tokenId];
        require(auc.active, "Not active");
        require(block.timestamp < auc.endTime, "Auction ended");
        require(msg.sender != auc.seller, "Seller cannot bid");
        require(amount >= auc.minBid && amount > auc.highestBid, "Bid too low");

        // Pull funds from bidder first
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        // If there is an existing highest bidder, add their funds to pendingReturns (pull to them)
        if (auc.highestBid > 0) {
            pendingReturns[auc.highestBidder] += auc.highestBid;
        }

        // Update highest
        auc.highestBid = amount;
        auc.highestBidder = msg.sender;

        emit BidPlaced(tokenId, msg.sender, amount);
    }

    /// @notice Withdraw refundable funds for outbid bidders
    function withdrawReturns() external nonReentrant {
        uint256 amount = pendingReturns[msg.sender];
        require(amount > 0, "No returns");
        pendingReturns[msg.sender] = 0;
        paymentToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Cancel an auction before any bids have been placed. Returns NFT to seller.
    function cancelAuction(uint256 tokenId) external nonReentrant {
        Auction storage auc = auctions[tokenId];
        require(auc.active, "Not active");
        require(auc.seller == msg.sender || msg.sender == owner(), "Not seller/owner");
        require(auc.highestBid == 0, "Has bids");

        auc.active = false;
        // Return NFT to seller via escrow release
        escrow.releaseAsset(tokenId, auc.seller);

        emit AuctionCancelled(tokenId, auc.seller);
        delete auctions[tokenId];
    }

    /// @notice Finalize auction after end time. Transfers NFT and distributes funds.
    function finalizeAuction(uint256 tokenId) external nonReentrant {
        Auction storage auc = auctions[tokenId];
        require(auc.active, "Not active or already finalized");
        require(block.timestamp >= auc.endTime, "Too early");

        // mark inactive before external calls for safety
        auc.active = false;

        if (auc.highestBid == 0) {
            // No bids: return NFT to seller
            escrow.releaseAsset(tokenId, auc.seller);
            delete auctions[tokenId];
            emit AuctionSettled(tokenId, address(0), 0, 0, 0);
            return;
        }

        uint256 finalPrice = auc.highestBid;
        address winner = auc.highestBidder;

        // Calculate platform fee
        uint256 platformFee = (finalPrice * platformFeeBps) / BPS_DENOMINATOR;

        // Distribute royalties from contract. royaltyPaid is moved out of contract by royaltyManager.
        uint256 royaltyPaid = 0;
        if (address(royaltyManager) != address(0)) {
            royaltyPaid = royaltyManager.distributeRoyaltyFromContract(tokenId, finalPrice);
            require(royaltyPaid <= finalPrice, "Invalid royalty");
        }

        // Remaining to seller after royalty and platform fee
        require(finalPrice >= platformFee + royaltyPaid, "Not enough to cover fees");
        uint256 sellerProceeds = finalPrice - platformFee - royaltyPaid;

        // Transfer platform fee to treasury
        if (platformFee > 0) {
            paymentToken.safeTransfer(treasury, platformFee);
        }

        // Transfer seller proceeds
        if (sellerProceeds > 0) {
            paymentToken.safeTransfer(auc.seller, sellerProceeds);
        }

        // Transfer NFT to winner
        escrow.releaseAsset(tokenId, winner);

        emit AuctionSettled(tokenId, winner, finalPrice, royaltyPaid, platformFee);

        // clean up
        delete auctions[tokenId];
    }

    /// @notice Force-forfeit auction collateral to seller (owner-only emergency)
    function forfeitAuctionCollateral(uint256 tokenId) external onlyOwner nonReentrant {
        Auction storage auc = auctions[tokenId];
        require(auc.active, "Not active");
        // mark inactive to avoid reuse
        auc.active = false;

        escrow.forfeitAsset(tokenId, auc.seller);
        // Refund highest bidder if present
        if (auc.highestBid > 0) {
            pendingReturns[auc.highestBidder] += auc.highestBid;
        }

        emit AuctionCancelled(tokenId, auc.seller);
        delete auctions[tokenId];
    }

    /* ============ Views ============ */

    function getAuction(uint256 tokenId) external view returns (
        address seller,
        uint256 minBid,
        uint256 endTime,
        address highestBidder,
        uint256 highestBid,
        bool active
    ) {
        Auction memory a = auctions[tokenId];
        return (a.seller, a.minBid, a.endTime, a.highestBidder, a.highestBid, a.active);
    }
}
