// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBase.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IStakingRewards {
    function getEligibleAddresses() external view returns (address[] memory);
}

contract SecretJackpot is VRFConsumerBase, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 internal keyHash;
    uint256 internal fee;

    IStakingRewards public stakingContract;
    uint256 public jackpotAmount;
    address public paymentToken;
    uint256 public lastJackpotTimestamp;
    uint256 public cooldownPeriod = 1 days;

    event JackpotRequested(bytes32 requestId);
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

    function triggerJackpot() external onlyOwner onlyCooldownPassed returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");

        address[] memory eligible = stakingContract.getEligibleAddresses();
        require(eligible.length > 0, "No eligible users");

        // Ensure jackpot funds are available before requesting randomness to avoid stuck state in callback
        require(IERC20(paymentToken).balanceOf(address(this)) >= jackpotAmount, "Insufficient jackpot funds");

        lastJackpotTimestamp = block.timestamp;
        requestId = requestRandomness(keyHash, fee);
        emit JackpotRequested(requestId);
    }

    function fulfillRandomness(bytes32, uint256 randomness) internal override nonReentrant {
        address[] memory eligible = stakingContract.getEligibleAddresses();
        if (eligible.length == 0 || jackpotAmount == 0) return;

        uint256 winnerIndex = randomness % eligible.length;
        address winner = eligible[winnerIndex];

        uint256 contractBalance = IERC20(paymentToken).balanceOf(address(this));
        uint256 payout = jackpotAmount > contractBalance ? contractBalance : jackpotAmount;

        require(payout > 0, "No funds for jackpot");

        IERC20(paymentToken).safeTransfer(winner, payout);

        emit JackpotWon(winner, payout);
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
        require(_staking != address(0), "Invalid staking contract");
        stakingContract = IStakingRewards(_staking);
    }

    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        paymentToken = _token;
    }

    function withdrawLINK(address to) external onlyOwner nonReentrant {
    uint256 balance = LINK.balanceOf(address(this));
    require(balance > 0, "No LINK");
    LinkTokenInterface linkToken = LinkTokenInterface(address(LINK));
    IERC20(address(LINK)).safeTransfer(to, balance);
    }
}
