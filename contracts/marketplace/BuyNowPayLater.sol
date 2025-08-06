// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEscrowManager {
    function lockAsset(address nft, uint256 tokenId) external;
    function releaseAsset(address nft, uint256 tokenId, address to) external;
}

contract BuyNowPayLater is Ownable {
    IERC20 public paymentToken;
    IERC721 public nft;
    IEscrowManager public escrow;

    uint256 public defaultInstallments = 3;

    struct BNPL {
        address buyer;
        uint256 totalPrice;
        uint256 downPayment;
        uint256 paid;
        uint256 deadline;
        uint8 installments;
    }

    mapping(uint256 => BNPL) public plans;

    event BNPLStarted(uint256 tokenId, address buyer);
    event InstallmentPaid(uint256 tokenId, uint256 amount);
    event BNPLDefaulted(uint256 tokenId);

    constructor(address _nft, address _token, address _escrow) {
        nft = IERC721(_nft);
        paymentToken = IERC20(_token);
        escrow = IEscrowManager(_escrow);
    }

    function initiateBNPL(uint256 tokenId, uint256 totalPrice, uint256 downPayment) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(totalPrice > 0 && downPayment > 0, "Invalid terms");

        nft.transferFrom(msg.sender, address(escrow), tokenId);
        escrow.lockAsset(address(nft), tokenId);

        plans[tokenId] = BNPL({
            buyer: msg.sender,
            totalPrice: totalPrice,
            downPayment: downPayment,
            paid: downPayment,
            deadline: block.timestamp + 30 days,
            installments: uint8(defaultInstallments)
        });

        emit BNPLStarted(tokenId, msg.sender);
    }

    function payInstallment(uint256 tokenId, uint256 amount) external {
        BNPL storage plan = plans[tokenId];
        require(plan.buyer == msg.sender, "Not buyer");
        require(block.timestamp <= plan.deadline, "Deadline passed");
        require(plan.paid + amount <= plan.totalPrice, "Overpay");

        paymentToken.transferFrom(msg.sender, address(this), amount);
        plan.paid += amount;

        emit InstallmentPaid(tokenId, amount);

        if (plan.paid == plan.totalPrice) {
            escrow.releaseAsset(address(nft), tokenId, plan.buyer);
            delete plans[tokenId];
        }
    }

    function defaulted(uint256 tokenId) external onlyOwner {
        BNPL storage plan = plans[tokenId];
        require(block.timestamp > plan.deadline, "Still active");

        escrow.releaseAsset(address(nft), tokenId, owner());
        delete plans[tokenId];

        emit BNPLDefaulted(tokenId);
    }

    function setInstallments(uint8 count) external onlyOwner {
        require(count > 0 && count <= 12, "Invalid count");
        defaultInstallments = count;
    }
}
