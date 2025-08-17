// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoostEngine is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public paymentToken;
    address public treasury;

    // Fee per day in payment token units (decimals as per token)
    uint256 public boostFeePerDay = 5 * 10**18;

    mapping(uint256 => uint256) public boostedUntil;

    event NFTBoosted(uint256 indexed tokenId, address indexed user, uint256 daysCount, uint256 boostedUntil);

    constructor(address _token, address _treasury) {
        require(_token != address(0), "Invalid payment token");
        require(_treasury != address(0), "Invalid treasury");
        paymentToken = IERC20(_token);
        treasury = _treasury;
    }

    /// @notice Boost NFT for a number of days
    function boostNFT(uint256 tokenId, uint256 daysCount) external {
        require(daysCount > 0, "Invalid boost period");
        require(treasury != address(0), "Treasury not set");

        uint256 fee = daysCount * boostFeePerDay;

        // Transfer fee safely to treasury
        paymentToken.safeTransferFrom(msg.sender, treasury, fee);

        uint256 currentEnd = boostedUntil[tokenId];
        uint256 newEnd = block.timestamp + (daysCount * 1 days);

        // Extend if already boosted
        if (currentEnd > block.timestamp) {
            boostedUntil[tokenId] = currentEnd + (daysCount * 1 days);
        } else {
            boostedUntil[tokenId] = newEnd;
        }

        emit NFTBoosted(tokenId, msg.sender, daysCount, boostedUntil[tokenId]);
    }

    function setBoostFeePerDay(uint256 newFee) external onlyOwner {
        boostFeePerDay = newFee;
    }

    function setPaymentToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        paymentToken = IERC20(_token);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function isBoosted(uint256 tokenId) external view returns (bool) {
        return boostedUntil[tokenId] >= block.timestamp;
    }
}
