// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTMinting is ERC721URIStorage, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    Counters.Counter private _tokenIds;

    IERC20 public paymentToken; // MFH token
    uint256 public mintPrice = 10 * 10**18;
    uint256 public maxPerWallet = 5;

    mapping(address => uint256) public mintedBy;

    event NFTMinted(address indexed user, uint256 tokenId);
    event FeesWithdrawn(address indexed to, uint256 amount);

    constructor(address _paymentToken) ERC721("MemeNFT", "MEME") {
        require(_paymentToken != address(0), "Payment token cannot be zero");
        paymentToken = IERC20(_paymentToken);
    }

    function mintNFT(string memory metadataURI) external {
        require(bytes(metadataURI).length > 0, "Invalid metadata URI");
        require(mintedBy[msg.sender] < maxPerWallet, "Mint limit exceeded");

        // Collect MFH fee safely
    paymentToken.safeTransferFrom(msg.sender, address(this), mintPrice);

        _tokenIds.increment();
        uint256 newId = _tokenIds.current();

        _safeMint(msg.sender, newId);
        _setTokenURI(newId, metadataURI);

        mintedBy[msg.sender]++;
        emit NFTMinted(msg.sender, newId);
    }

    function setMintPrice(uint256 _price) external onlyOwner {
        mintPrice = _price;
    }

    function setMaxPerWallet(uint256 _max) external onlyOwner {
        maxPerWallet = _max;
    }

    function withdrawFees(address to) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        uint256 balance = paymentToken.balanceOf(address(this));
    paymentToken.safeTransfer(to, balance);
        emit FeesWithdrawn(to, balance);
    }
}
