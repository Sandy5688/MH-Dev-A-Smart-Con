// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice RoyaltyManager compatible with MarketplaceCore pull-from-contract flow.
contract RoyaltyManager is Ownable {
    using SafeERC20 for IERC20;

    uint256 public platformCut = 200; // 2% of royalty amount
    uint256 public constant MAX_ROYALTY = 1000; // 10% max royalty

    address public platformTreasury;
    IERC20 public paymentToken;

    struct Royalty {
        uint256 percent; // out of 10,000 (basis points)
        address creator;
    }

    mapping(uint256 => Royalty) public royalties;

    event RoyaltySet(uint256 indexed tokenId, address indexed creator, uint256 percent);
    event RoyaltyPaid(uint256 indexed tokenId, address indexed creator, uint256 totalRoyalty, uint256 creatorAmount, uint256 platformAmount);

    constructor(address _paymentToken, address _treasury) {
        require(_paymentToken != address(0), "Invalid payment token");
        require(_treasury != address(0), "Invalid treasury");
        paymentToken = IERC20(_paymentToken);
        platformTreasury = _treasury;
    }

    /// @notice Set royalty info for a tokenId.
    function setRoyalty(uint256 tokenId, address creator, uint256 percent) external onlyOwner {
        require(percent <= MAX_ROYALTY, "Royalty too high");
        require(creator != address(0), "Invalid creator");
        royalties[tokenId] = Royalty(percent, creator);
        emit RoyaltySet(tokenId, creator, percent);
    }

    /// @notice Called by marketplace to distribute royalty from funds already held in contract.
    /// @dev Transfers from this contract's balance, not from buyer.
    /// @return totalRoyalty amount taken from marketplace funds.
    function distributeRoyaltyFromContract(uint256 tokenId, uint256 salePrice) external returns (uint256 totalRoyalty) {
        Royalty memory r = royalties[tokenId];
        if (r.percent == 0 || r.creator == address(0)) {
            return 0; // No royalty set, skip.
        }

        totalRoyalty = (salePrice * r.percent) / 10000;
        uint256 platformAmount = (totalRoyalty * platformCut) / 10000;
        uint256 creatorAmount = totalRoyalty - platformAmount;

        // Transfer from marketplace's contract balance
            // Pull funds from caller (marketplace/auction) and forward to recipients
            paymentToken.safeTransferFrom(msg.sender, r.creator, creatorAmount);
            if (platformAmount > 0) {
                paymentToken.safeTransferFrom(msg.sender, platformTreasury, platformAmount);
            }

        emit RoyaltyPaid(tokenId, r.creator, totalRoyalty, creatorAmount, platformAmount);
    }

    function setPlatformCut(uint256 cutBps) external onlyOwner {
        require(cutBps <= 1000, "Max 10%");
        platformCut = cutBps;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury");
        platformTreasury = newTreasury;
    }
}
