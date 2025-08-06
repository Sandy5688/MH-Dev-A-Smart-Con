// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NFTMinting is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    address public paymentToken; // MFH token
    uint256 public mintPrice = 10 * 10 ** 18;
    uint256 public maxPerWallet = 5;

    mapping(address => uint256) public mintedBy;

    event NFTMinted(address indexed user, uint256 tokenId);

    constructor(address _paymentToken) ERC721("MemeNFT", "MEME") {
        paymentToken = _paymentToken;
    }

    function mintNFT(string memory metadataURI) external {
        require(bytes(metadataURI).length > 0, "Invalid metadata URI");
        require(mintedBy[msg.sender] < maxPerWallet, "Mint limit exceeded");

        // Collect MFH fee
        IERC20(paymentToken).transferFrom(msg.sender, address(this), mintPrice);

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
        uint256 balance = IERC20(paymentToken).balanceOf(address(this));
        require(IERC20(paymentToken).transfer(to, balance), "Withdraw failed");
    }
}
