// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CheckInReward is Ownable {
    IERC20 public token;
    uint256 public rewardAmount;

    // Tracks the last day (UTC) a user checked in
    mapping(address => uint256) public lastCheckInDay;

    event CheckedIn(address indexed user, uint256 reward);

    constructor(address _mfh, uint256 _rewardAmount) {
        require(_mfh != address(0), "Invalid token");
        token = IERC20(_mfh);
        rewardAmount = _rewardAmount;
    }

    function checkIn() external {
        uint256 currentDay = block.timestamp / 1 days;
        require(lastCheckInDay[msg.sender] < currentDay, "Already checked in today");

        lastCheckInDay[msg.sender] = currentDay;

        require(token.balanceOf(address(this)) >= rewardAmount, "Out of rewards");
        require(token.transfer(msg.sender, rewardAmount), "Transfer failed");

        emit CheckedIn(msg.sender, rewardAmount);
    }

    // ----------------------------
    // Admin functions
    // ----------------------------

    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
    }

    function setRewardAmount(uint256 _amount) external onlyOwner {
        rewardAmount = _amount;
    }
}
