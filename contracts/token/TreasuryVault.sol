// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TreasuryVault is Ownable {
    address public multisig;

    event DepositReceived(address indexed token, address indexed from, uint256 amount);
    event WithdrawalExecuted(address indexed token, address indexed to, uint256 amount);
    event ERC20Recovered(address indexed token, address indexed to, uint256 amount);
    event ETHRecovered(address indexed to, uint256 amount);

    constructor(address _multisig) {
        require(_multisig != address(0), "Vault: invalid multisig");
        multisig = _multisig;
    }

    modifier onlyAdmin() {
        require(msg.sender == owner() || msg.sender == multisig, "Vault: not authorized");
        _;
    }

    // Deposit ERC20 into vault
    function deposit(address token, uint256 amount) external {
        require(amount > 0, "Vault: zero amount");
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Vault: deposit failed");
        emit DepositReceived(token, msg.sender, amount);
    }

    // Withdraw ERC20 from vault
    function withdraw(address token, address to, uint256 amount) external onlyAdmin {
        require(to != address(0), "Vault: invalid recipient");
        require(amount > 0, "Vault: zero amount");
        require(IERC20(token).transfer(to, amount), "Vault: withdraw failed");
        emit WithdrawalExecuted(token, to, amount);
    }

    // Recover ERC20 stuck in vault (emergency)
    function recoverERC20(address token, address to, uint256 amount) external onlyAdmin {
        require(to != address(0), "Vault: invalid recipient");
        require(amount > 0, "Vault: zero amount");
        require(IERC20(token).transfer(to, amount), "Vault: recover failed");
        emit WithdrawalExecuted(token, to, amount); // Use same event as withdraw
    }

    // Recover stuck ETH
    function recoverETH(address payable to, uint256 amount) external onlyAdmin {
        require(to != address(0), "Vault: zero address");
        require(amount > 0, "Vault: zero amount");
        require(address(this).balance >= amount, "Vault: insufficient ETH");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Vault: ETH transfer failed");
        emit ETHRecovered(to, amount);
    }

    // Update multisig
    function setMultisig(address _newMultisig) external onlyOwner {
        require(_newMultisig != address(0), "Vault: zero address");
        multisig = _newMultisig;
    }

    // View ERC20 balance of a token
    function balanceOf(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // Fallback to accept ETH deposits
    receive() external payable {
        emit DepositReceived(address(0), msg.sender, msg.value);
    }
}
