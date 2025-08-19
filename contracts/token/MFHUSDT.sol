// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MFHUSDT is ERC20, Ownable, Pausable, ERC2771Context, ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint8 private constant _decimals = 6;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** _decimals;
    uint256 public totalMinted;

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    constructor(address trustedForwarder) ERC20("MetaFunHub USD", "MFHUSDT") ERC2771Context(trustedForwarder) {
        totalMinted = 0;
    }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "MFHUSDT: max supply exceeded");
        _mint(to, amount);
        totalMinted += amount;
        emit Mint(to, amount);
    }

    function burn(address account, uint256 amount) external {
        require(_msgSender() == account || allowance(account, _msgSender()) >= amount, "MFHUSDT: not allowed");
        if (_msgSender() != account) {
            _spendAllowance(account, _msgSender(), amount);
        }
        _burn(account, amount);
        emit Burn(account, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal override whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    // ERC2771 + Context overrides
    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
}
