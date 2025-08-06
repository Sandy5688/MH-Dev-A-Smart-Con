// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CheckInReward is Ownable {
    IERC20 public token;
    uint256 public rewardAmount;
    mapping(address => uint256) public lastCheckIn;

    event CheckedIn(address indexed user, uint256 reward);

    constructor(address _mfh, uint256 _rewardAmount) {
        token = IERC20(_mfh);
        rewardAmount = _rewardAmount;
    }

    function checkIn() external {
        require(block.timestamp - lastCheckIn[msg.sender] >= 1 days, "Already checked in today");
        lastCheckIn[msg.sender] = block.timestamp;

        require(token.balanceOf(address(this)) >= rewardAmount, "Out of rewards");
        token.transfer(msg.sender, rewardAmount);

        emit CheckedIn(msg.sender, rewardAmount);
    }

    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
    }

    function setRewardAmount(uint256 _amount) external onlyOwner {
        rewardAmount = _amount;
    }
}
