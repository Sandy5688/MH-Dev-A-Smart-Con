// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRoyaltyManager {
    function distributeRoyalty(address creator, uint256 amount) external;
}
