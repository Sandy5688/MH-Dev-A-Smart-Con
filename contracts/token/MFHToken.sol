// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract MFHToken is ERC20, Ownable, Pausable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public totalMinted;

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    constructor() ERC20("MetaFunHub", "MFH") {
        _mint(msg.sender, MAX_SUPPLY);
        totalMinted = MAX_SUPPLY;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "MFH: max supply exceeded");
        _mint(to, amount);
        totalMinted += amount;
        emit Mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
        emit Burn(from, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal override whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}
