// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BoostEngine is Ownable {
    IERC20 public paymentToken;
    address public treasury;

    uint256 public boostRatePerDay = 5 * 10 ** 18;

    mapping(uint256 => uint256) public boostedUntil;

    event NFTBoosted(uint256 tokenId, address user, uint256 duration);

    constructor(address _token, address _treasury) {
        paymentToken = IERC20(_token);
        treasury = _treasury;
    }

    function boostNFT(uint256 tokenId, uint256 daysCount) external {
        require(daysCount > 0, "Invalid boost period");
        uint256 fee = daysCount * boostRatePerDay;

        // Transfer boost fee to treasury
        IERC20(paymentToken).transferFrom(msg.sender, treasury, fee);

        uint256 currentEnd = boostedUntil[tokenId];
        uint256 newEnd = block.timestamp + (daysCount * 1 days);

        // Extend if already boosted
        if (currentEnd > block.timestamp) {
            boostedUntil[tokenId] = currentEnd + (daysCount * 1 days);
        } else {
            boostedUntil[tokenId] = newEnd;
        }

        emit NFTBoosted(tokenId, msg.sender, daysCount);
    }

    function setBoostRate(uint256 newRate) external onlyOwner {
        boostRatePerDay = newRate;
    }

    function setPaymentToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        paymentToken = IERC20(_token);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    function isBoosted(uint256 tokenId) external view returns (bool) {
        return boostedUntil[tokenId] >= block.timestamp;
    }
}
