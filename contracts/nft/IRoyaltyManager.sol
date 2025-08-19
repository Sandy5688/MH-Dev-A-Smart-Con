// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRoyaltyManager {
    function setRoyalty(uint256 tokenId, address creator, uint256 percent) external;
    function distributeRoyaltyFromContract(uint256 tokenId, uint256 salePrice) external returns (uint256);
    function setPlatformCut(uint256 cutBps) external;
    function setTreasury(address newTreasury) external;
}
