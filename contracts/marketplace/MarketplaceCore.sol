// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @notice Royalty manager interface for marketplace-pulls-funds pattern.
/// The royalty manager will transfer royalty amounts from the marketplace contract
/// to the royalty recipients and return the total royalty amount paid.
interface IRoyaltyManager {
    /// @notice Distribute royalty from marketplace contract funds and return total royalty paid.
    /// @param tokenId nft id
    /// @param salePrice sale price passed (in paymentToken units)
    /// @return royaltyAmount amount of paymentToken transferred to royalty recipients
    function distributeRoyaltyFromContract(uint256 tokenId, uint256 salePrice) external returns (uint256);
}

contract MarketplaceCore is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    IERC20 public paymentToken;
    IERC721 public nft;
    address public treasury;
    IRoyaltyManager public royaltyManager;

    uint256 public platformFeeBps = 500; // 5%
    uint256 public constant BPS_DENOMINATOR = 10000;

    struct Listing {
        address seller;
        uint256 price;
    }

    mapping(uint256 => Listing) public listings;

    event ListingCreated(uint256 indexed tokenId, address indexed seller, uint256 price);
    event ListingCancelled(uint256 indexed tokenId, address indexed seller);
    event ItemSold(uint256 indexed tokenId, address indexed buyer, uint256 price, uint256 sellerAmount, uint256 royaltyAmount, uint256 platformFee);

    constructor(address _nft, address _paymentToken, address _treasury, address _royaltyManager) {
        require(_nft != address(0), "Invalid nft");
        require(_paymentToken != address(0), "Invalid payment token");
        require(_treasury != address(0), "Invalid treasury");

        nft = IERC721(_nft);
        paymentToken = IERC20(_paymentToken);
        treasury = _treasury;
        if (_royaltyManager != address(0)) {
            royaltyManager = IRoyaltyManager(_royaltyManager);
        }
    }

    /* ========================= admin ========================= */

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    function setRoyaltyManager(address _rm) external onlyOwner {
        royaltyManager = IRoyaltyManager(_rm);
    }

    function setPlatformFee(uint256 bps) external onlyOwner {
        require(bps <= 1000, "Max 10%");
        platformFeeBps = bps;
    }

    /* ========================= listings ========================= */

    /// @notice List an NFT for sale. Transfers NFT into marketplace custody.
    function listNFT(uint256 tokenId, uint256 price) external nonReentrant {
        require(price > 0, "Invalid price");
        require(nft.ownerOf(tokenId) == msg.sender, "Not the owner");
        require(listings[tokenId].price == 0, "Already listed");

        // Move NFT into marketplace custody (caller must approve)
        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        listings[tokenId] = Listing({
            seller: msg.sender,
            price: price
        });

        emit ListingCreated(tokenId, msg.sender, price);
    }

    /// @notice Cancel a listing and return NFT to seller.
    function cancelListing(uint256 tokenId) external nonReentrant {
        Listing memory listing = listings[tokenId];
        require(listing.price > 0, "Not listed");
        require(listing.seller == msg.sender || msg.sender == owner(), "Not seller or owner");

        delete listings[tokenId];

        // Return NFT to seller
        nft.safeTransferFrom(address(this), listing.seller, tokenId);

        emit ListingCancelled(tokenId, listing.seller);
    }

    /// @notice Buy a listed NFT. Buyer must approve paymentToken allowance to this contract.
    /// Payment flow:
    /// 1) Pull full price from buyer into this contract.
    /// 2) Call royaltyManager.distributeRoyaltyFromContract(...) if set — it should pull its share from the contract and return amount paid.
    /// 3) Pay platform fee to treasury.
    /// 4) Pay remaining seller amount to seller.
    /// 5) Transfer NFT to buyer.
    function buyNFT(uint256 tokenId) external nonReentrant {
        Listing memory listing = listings[tokenId];
        require(listing.price > 0, "Not listed");
        require(listing.seller != msg.sender, "Seller cannot buy own listing");

        // remove listing early to prevent reentrancy/order issues
        delete listings[tokenId];

        uint256 price = listing.price;

        // Pull funds from buyer to marketplace first
        paymentToken.safeTransferFrom(msg.sender, address(this), price);

        // Compute platform fee
        uint256 platformFee = (price * platformFeeBps) / BPS_DENOMINATOR;

        // Distribute royalties from contract, if manager present.
        uint256 royaltyPaid = 0;
        if (address(royaltyManager) != address(0)) {
            // Approve royalty manager to pull royalty from this contract's balance.
            // The manager will call transferFrom(msg.sender=marketplace, ...) to move funds out.
            IERC20(paymentToken).approve(address(royaltyManager), price);
            royaltyPaid = royaltyManager.distributeRoyaltyFromContract(tokenId, price);
            require(royaltyPaid <= price, "Invalid royalty");
        }

        // Remaining to seller after royalty and platform fee
        require(price >= platformFee + royaltyPaid, "Insufficient price after fees");
        uint256 sellerAmount = price - platformFee - royaltyPaid;

        // Transfer fee to treasury first
        if (platformFee > 0) {
            paymentToken.safeTransfer(treasury, platformFee);
        }

        // Transfer seller proceeds
        if (sellerAmount > 0) {
            paymentToken.safeTransfer(listing.seller, sellerAmount);
        }

        // Transfer NFT to buyer
        nft.safeTransferFrom(address(this), msg.sender, tokenId);

        emit ItemSold(tokenId, msg.sender, price, sellerAmount, royaltyPaid, platformFee);
    }

    /* ========================= views ========================= */

    function getListing(uint256 tokenId) external view returns (address seller, uint256 price) {
        Listing memory l = listings[tokenId];
        return (l.seller, l.price);
    }

    /* ========================= ERC721 Receiver ========================= */

    /// @notice Accept safe transfers into marketplace (in case someone calls safeTransferTo marketplace directly).
    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
