// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStakingRewards {
    function getEligibleAddresses() external view returns (address[] memory);
}

contract SecretJackpot is VRFConsumerBase, Ownable {
    bytes32 internal keyHash;
    uint256 internal fee;

    IStakingRewards public stakingContract;
    uint256 public jackpotAmount;
    address public paymentToken;
    uint256 public lastJackpotTimestamp;
    uint256 public cooldownPeriod = 1 days;

    address[] public lastEligibleList;

    event JackpotRequested(uint256 requestId);
    event JackpotWon(address winner, uint256 amount);
    event EligibilityRulesUpdated(uint256 cooldownPeriod, uint256 jackpotAmount);

    constructor(
        address _stakingRewards,
        address _vrfCoordinator,
        address _linkToken,
        bytes32 _keyHash,
        uint256 _fee,
        address _paymentToken,
        uint256 _jackpotAmount
    ) VRFConsumerBase(_vrfCoordinator, _linkToken) {
        stakingContract = IStakingRewards(_stakingRewards);
        keyHash = _keyHash;
        fee = _fee;
        paymentToken = _paymentToken;
        jackpotAmount = _jackpotAmount;
    }

    modifier onlyCooldownPassed() {
        require(block.timestamp >= lastJackpotTimestamp + cooldownPeriod, "Cooldown not met");
        _;
    }

    function triggerJackpot() external onlyCooldownPassed returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");

        lastEligibleList = stakingContract.getEligibleAddresses();
        require(lastEligibleList.length > 0, "No eligible users");

        lastJackpotTimestamp = block.timestamp;
        requestId = requestRandomness(keyHash, fee);
        emit JackpotRequested(uint256(requestId));
    }

    function fulfillRandomness(bytes32, uint256 randomness) internal override {
        uint256 winnerIndex = randomness % lastEligibleList.length;
        address winner = lastEligibleList[winnerIndex];

        require(
            IERC20(paymentToken).transfer(winner, jackpotAmount),
            "Transfer failed"
        );

        emit JackpotWon(winner, jackpotAmount);
    }

    // ----------------------------
    // Admin functions
    // ----------------------------

    function setEligibilityRules(uint256 _cooldown, uint256 _amount) external onlyOwner {
        cooldownPeriod = _cooldown;
        jackpotAmount = _amount;
        emit EligibilityRulesUpdated(_cooldown, _amount);
    }

    function setStakingContract(address _staking) external onlyOwner {
        stakingContract = IStakingRewards(_staking);
    }

    function setToken(address _token) external onlyOwner {
        paymentToken = _token;
    }

    function withdrawLINK(address to) external onlyOwner {
        uint256 balance = LINK.balanceOf(address(this));
        require(LINK.transfer(to, balance), "LINK withdrawal failed");
    }
}
