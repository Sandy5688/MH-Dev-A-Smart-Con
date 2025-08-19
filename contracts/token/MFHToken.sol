// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract MFHToken is ERC20, Ownable, Pausable, ERC2771Context {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public totalMinted;

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    constructor(address trustedForwarder)
        ERC20("MetaFunHub", "MFH")
        ERC2771Context(trustedForwarder)
    {
        // Pre-mint to deployer if desired
        uint256 initialSupply = 500_000_000 * 10 ** decimals(); // half supply example
        _mint(_msgSender(), initialSupply);
        totalMinted = initialSupply;
    }

    /** Pause / unpause **/
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /** Minting **/
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalMinted + amount <= MAX_SUPPLY, "MFH: max supply exceeded");
        _mint(to, amount);
        totalMinted += amount;
        emit Mint(to, amount);
    }

    /** Burning **/
    function burn(address account, uint256 amount) external {
        address sender = _msgSender();
        require(amount > 0, "MFH: cannot burn 0");
        
        // Check if sender is burning their own tokens or has allowance
        if (account == sender) {
            // Can only burn tokens directly from own account
            require(balanceOf(account) >= amount, "MFH: burn amount exceeds balance");
            require(sender == account, "MFH: not allowed to burn");
            _burn(account, amount);
        } else {
            // Must have allowance to burn others' tokens
            uint256 currentAllowance = allowance(account, sender);
            require(currentAllowance >= amount, "MFH: not allowed to burn");
            _spendAllowance(account, sender, amount);
            _burn(account, amount);
        }

        emit Burn(account, amount);
    }

    /** Override _msgSender for ERC2771 meta-tx support **/
    function _msgSender() internal view override(Context, ERC2771Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /** Pause transfer hooks **/
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal override whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}
