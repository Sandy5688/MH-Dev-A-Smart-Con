// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TreasuryVault is Ownable {
    address public multisig;

    event DepositReceived(address indexed token, address indexed from, uint256 amount);
    event WithdrawalExecuted(address indexed token, address indexed to, uint256 amount);

    constructor(address _multisig) {
        multisig = _multisig;
    }

    modifier onlyAdmin() {
        require(msg.sender == owner() || msg.sender == multisig, "Vault: not authorized");
        _;
    }

    function deposit(address token, uint256 amount) external {
        require(amount > 0, "Vault: zero amount");
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Vault: deposit failed");
        emit DepositReceived(token, msg.sender, amount);
    }

    function withdraw(address token, address to, uint256 amount) external onlyAdmin {
        require(amount > 0, "Vault: zero amount");
        require(IERC20(token).transfer(to, amount), "Vault: withdraw failed");
        emit WithdrawalExecuted(token, to, amount);
    }

    function setMultisig(address _newMultisig) external onlyOwner {
        multisig = _newMultisig;
    }
}
