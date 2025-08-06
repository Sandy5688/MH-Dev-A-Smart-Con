// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract StakingRewards is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private stakers;

    IERC20 public token;

    uint256 public rewardRatePerSecond;
    uint256 public totalStaked;
    uint256 public penaltyPercent = 10;

    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastStaked;
    }

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);

    constructor(address _token) {
        token = IERC20(_token);
    }

    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Stake: zero amount");
        token.transferFrom(msg.sender, address(this), amount);

        _claimReward(msg.sender);

        stakes[msg.sender].amount += amount;
        stakes[msg.sender].lastStaked = block.timestamp;
        stakers.add(msg.sender); // Add to active set

        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    function unstake() external {
        StakeInfo storage user = stakes[msg.sender];
        require(user.amount > 0, "Unstake: nothing staked");

        uint256 stakedAmount = user.amount;
        uint256 reward = pendingReward(msg.sender);
        uint256 withdrawAmount = stakedAmount;

        if (block.timestamp < user.lastStaked + 7 days) {
            uint256 penalty = (reward * penaltyPercent) / 100;
            reward -= penalty;
        }

        user.amount = 0;
        user.rewardDebt = 0;
        stakers.remove(msg.sender); //  Remove from active set

        totalStaked -= stakedAmount;

        token.transfer(msg.sender, withdrawAmount);
        token.transfer(msg.sender, reward);

        emit Unstaked(msg.sender, stakedAmount, reward);
    }

    function claimReward() external {
        uint256 reward = _claimReward(msg.sender);
        emit RewardClaimed(msg.sender, reward);
    }

    function _claimReward(address userAddr) internal returns (uint256 reward) {
        reward = pendingReward(userAddr);
        if (reward > 0) {
            stakes[userAddr].rewardDebt = block.timestamp;
            token.transfer(userAddr, reward);
        }
    }

    function pendingReward(address userAddr) public view returns (uint256) {
        StakeInfo memory s = stakes[userAddr];
        if (s.amount == 0) return 0;

        uint256 timeElapsed = block.timestamp - s.rewardDebt;
        return (s.amount * rewardRatePerSecond * timeElapsed) / 1e18;
    }

    function setRewardRate(uint256 rate) external onlyOwner {
        rewardRatePerSecond = rate;
        emit RewardRateUpdated(rate);
    }

    function setPenaltyPercent(uint256 percent) external onlyOwner {
        require(percent <= 100, "Penalty too high");
        penaltyPercent = percent;
    }

    function getEligibleAddresses() external view returns (address[] memory) {
        uint256 length = stakers.length();
        address[] memory result = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = stakers.at(i);
        }
        return result;
    }
}
