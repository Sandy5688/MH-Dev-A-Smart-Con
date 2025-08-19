// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CheckInReward is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

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

    function checkIn() external nonReentrant {
        uint256 currentDay = block.timestamp / 1 days;
        require(lastCheckInDay[msg.sender] < currentDay, "Already checked in today");

        lastCheckInDay[msg.sender] = currentDay;

        require(token.balanceOf(address(this)) >= rewardAmount, "Out of rewards");
        token.safeTransfer(msg.sender, rewardAmount);

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

    // Owner pulls funds into the contract (owner must approve this contract first)
    function fund(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid amount");
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    // Withdraw remaining rewards
    function withdrawRewards(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        token.safeTransfer(to, amount);
    }
}
