// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RewardDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public mfh;

    event RewardSent(address indexed user, uint256 amount);
    event RewardDistributed(address[] users, uint256 totalAmount);

    constructor(address _mfh) {
        require(_mfh != address(0), "Invalid token");
        mfh = IERC20(_mfh);
    }

    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        mfh = IERC20(_token);
    }

    function distribute(address[] calldata users, uint256[] calldata amounts) external onlyOwner nonReentrant {
        require(users.length == amounts.length, "Mismatched arrays");
        require(users.length > 0, "Empty arrays");

        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(users[i] != address(0), "Invalid user");
            require(amounts[i] > 0, "Invalid amount");
            total += amounts[i];
        }

        require(mfh.balanceOf(address(this)) >= total, "Insufficient funds");

        for (uint256 i = 0; i < users.length; i++) {
            mfh.safeTransfer(users[i], amounts[i]);
            emit RewardSent(users[i], amounts[i]);
        }

        emit RewardDistributed(users, total);
    }

    // Withdraw leftover tokens safely
    function withdrawLeftover(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        mfh.safeTransfer(to, amount);
    }

    // Optional: chunked distribution to avoid OOG
    function distributeChunk(address[] calldata users, uint256[] calldata amounts, uint256 start, uint256 count) external onlyOwner nonReentrant {
        require(users.length == amounts.length, "Mismatched arrays");
        require(start < users.length, "Invalid start");
        uint256 end = start + count;
        if (end > users.length) end = users.length;

        uint256 total = 0;
        for (uint256 i = start; i < end; i++) {
            require(users[i] != address(0), "Invalid user");
            require(amounts[i] > 0, "Invalid amount");
            total += amounts[i];
        }

        require(mfh.balanceOf(address(this)) >= total, "Insufficient funds");

        for (uint256 i = start; i < end; i++) {
            mfh.safeTransfer(users[i], amounts[i]);
            emit RewardSent(users[i], amounts[i]);
        }
    }
}
