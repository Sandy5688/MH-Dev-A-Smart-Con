// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RoyaltyManager is Ownable {
    uint256 public platformCut = 200; // 2% = 200 basis points
    uint256 public constant MAX_ROYALTY = 1000; // 10%

    address public platformTreasury;
    address public paymentToken;

    struct Royalty {
        uint256 percent; // out of 10,000 (basis points)
        address creator;
    }

    mapping(uint256 => Royalty) public royalties;

    event RoyaltySet(uint256 tokenId, address creator, uint256 percent);
    event RoyaltyPaid(uint256 tokenId, address to, uint256 amount, address buyer);

    constructor(address _paymentToken, address _treasury) {
        paymentToken = _paymentToken;
        platformTreasury = _treasury;
    }

    function setRoyalty(uint256 tokenId, address creator, uint256 percent) external onlyOwner {
        require(percent <= MAX_ROYALTY, "Royalty too high");
        royalties[tokenId] = Royalty(percent, creator);
        emit RoyaltySet(tokenId, creator, percent);
    }

    function distributeRoyalty(uint256 tokenId, uint256 salePrice, address buyer) external {
        Royalty memory r = royalties[tokenId];
        require(r.percent > 0, "No royalty set");

        uint256 royaltyAmount = (salePrice * r.percent) / 10000;
        uint256 platformAmount = (royaltyAmount * platformCut) / 10000;
        uint256 creatorAmount = royaltyAmount - platformAmount;

        // Pull funds from buyer (approved beforehand)
        require(IERC20(paymentToken).transferFrom(buyer, r.creator, creatorAmount), "Creator royalty failed");
        require(IERC20(paymentToken).transferFrom(buyer, platformTreasury, platformAmount), "Platform fee failed");

        emit RoyaltyPaid(tokenId, r.creator, royaltyAmount, buyer);
    }

    function setPlatformCut(uint256 cutBps) external onlyOwner {
        require(cutBps <= 1000, "Max 10%");
        platformCut = cutBps;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        platformTreasury = newTreasury;
    }
}
