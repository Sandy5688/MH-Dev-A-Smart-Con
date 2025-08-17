// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RewardDistributor is Ownable {
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

    function distribute(address[] calldata users, uint256[] calldata amounts) external onlyOwner {
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
            require(mfh.transfer(users[i], amounts[i]), "Transfer failed");
            emit RewardSent(users[i], amounts[i]);
        }

        emit RewardDistributed(users, total);
    }

    function withdrawLeftover(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(mfh.balanceOf(address(this)) >= amount, "Insufficient funds");
        require(mfh.transfer(to, amount), "Transfer failed");
    }
}
