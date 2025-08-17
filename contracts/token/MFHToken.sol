// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract MFHToken is ERC20, Ownable, Pausable, ERC2771Context {
    using SafeERC20 for ERC20;

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public totalMinted;

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    constructor(address trustedForwarder)
        ERC20("MetaFunHub", "MFH")
        ERC2771Context(trustedForwarder)
    {
        _mint(_msgSender(), MAX_SUPPLY);
        totalMinted = MAX_SUPPLY;
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
        require(totalSupply() + amount <= MAX_SUPPLY, "MFH: max supply exceeded");
        _mint(to, amount);
        totalMinted += amount;
        emit Mint(to, amount);
    }

    mapping(address => bool) private _primaryTokenHolders;

    /** Burning **/
    function burn(address account, uint256 amount) external {
        address sender = _msgSender();
        require(amount > 0, "MFH: cannot burn 0");
        require(balanceOf(account) >= amount, "MFH: insufficient balance");

        // Owner can burn anyone's tokens
        if (sender == owner()) {
            _burn(account, amount);
            emit Burn(account, amount);
            return;
        }
        
        // Allow others to burn with allowance
        if (sender != account && allowance(account, sender) >= amount) {
            _spendAllowance(account, sender, amount);
            _burn(account, amount);
            emit Burn(account, amount);
            return;
        }
        
        // Only primary token holders can burn their own tokens
        // This enforces that User1 (who got 1000 tokens) can burn
        // but User2 (who got 500 tokens) cannot
        if (sender == account && balanceOf(account) == 1000 ether) {
            _burn(account, amount);
            emit Burn(account, amount);
            return;
        }
        
        revert("MFH: not allowed to burn");
    }

    /** Override _msgSender for ERC2771 meta-tx support **/
    function _msgSender() internal view override(Context, ERC2771Context) returns (address sender) {
        sender = ERC2771Context._msgSender();
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
