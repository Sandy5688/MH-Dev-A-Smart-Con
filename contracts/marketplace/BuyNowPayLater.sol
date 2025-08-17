// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IEscrowManager {
    function lockAsset(uint256 tokenId, address owner) external;
    function releaseAsset(uint256 tokenId, address to) external;
    function forfeitAsset(uint256 tokenId, address to) external;
}

interface IRoyaltyManager {
    function distributeRoyaltyFromContract(uint256 tokenId, uint256 salePrice) external returns (uint256);
}

contract BuyNowPayLater is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable paymentToken;
    IERC721 public immutable nft;
    IEscrowManager public immutable escrow;
    IRoyaltyManager public royaltyManager;

    uint256 public defaultInstallments = 3;

    struct BNPL {
        address buyer;
        address seller;
        uint256 totalPrice;
        uint256 downPayment;
        uint256 paid;
        uint256 deadline;
        uint8 installments;
    }

    mapping(uint256 => BNPL) public plans;

    event BNPLStarted(
        uint256 indexed tokenId,
        address indexed buyer,
        address indexed seller,
        uint256 price,
        uint256 downPayment
    );
    event InstallmentPaid(uint256 indexed tokenId, uint256 amount, uint256 totalPaid);
    event BNPLCompleted(uint256 indexed tokenId, address indexed buyer);
    event BNPLDefaulted(uint256 indexed tokenId, address indexed seller);

    constructor(
        address _nft,
        address _token,
        address _escrow,
        address _royaltyManager
    ) {
        require(_nft != address(0) && _token != address(0) && _escrow != address(0) && _royaltyManager != address(0), "Invalid address");
        nft = IERC721(_nft);
        paymentToken = IERC20(_token);
        escrow = IEscrowManager(_escrow);
        royaltyManager = IRoyaltyManager(_royaltyManager);
    }

    function initiateBNPL(
        uint256 tokenId,
        uint256 totalPrice,
        uint256 downPayment,
        uint8 installments
    ) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(totalPrice > 0 && downPayment > 0, "Invalid terms");
        require(installments > 0, "Invalid installment count");
        require(downPayment < totalPrice, "Downpayment must be less than price");

    // Transfer NFT to escrow for custody: seller must approve escrow beforehand.
    escrow.lockAsset(tokenId, msg.sender);

        // Transfer downpayment to contract
        paymentToken.safeTransferFrom(msg.sender, address(this), downPayment);

        // Pay royalties from downpayment if applicable
        royaltyManager.distributeRoyaltyFromContract(tokenId, downPayment);

        plans[tokenId] = BNPL({
            buyer: address(0), // Buyer will pay installments
            seller: msg.sender,
            totalPrice: totalPrice,
            downPayment: downPayment,
            paid: downPayment,
            deadline: block.timestamp + (installments * 30 days),
            installments: installments
        });

        emit BNPLStarted(tokenId, address(0), msg.sender, totalPrice, downPayment);
    }

    function payInstallment(uint256 tokenId, uint256 amount) external {
        BNPL storage plan = plans[tokenId];
        require(plan.seller != address(0), "Plan not found");
        require(block.timestamp <= plan.deadline, "Deadline passed");
        require(amount > 0, "Invalid payment");
        require(plan.paid + amount <= plan.totalPrice, "Overpay");

        // If this is first installment, set buyer
        if (plan.buyer == address(0)) {
            plan.buyer = msg.sender;
        } else {
            require(plan.buyer == msg.sender, "Not buyer");
        }

        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        plan.paid += amount;

        emit InstallmentPaid(tokenId, amount, plan.paid);

        if (plan.paid >= plan.totalPrice) {
            escrow.releaseAsset(tokenId, plan.buyer);
            paymentToken.safeTransfer(plan.seller, plan.paid);
            emit BNPLCompleted(tokenId, plan.buyer);
            delete plans[tokenId];
        }
    }

    function markDefault(uint256 tokenId) external {
        BNPL storage plan = plans[tokenId];
        require(plan.seller != address(0), "Plan not found");
        require(block.timestamp > plan.deadline, "Still active");

        escrow.forfeitAsset(tokenId, plan.seller);
        emit BNPLDefaulted(tokenId, plan.seller);
        delete plans[tokenId];
    }

    function setInstallments(uint8 count) external onlyOwner {
        require(count > 0 && count <= 12, "Invalid count");
        defaultInstallments = count;
    }
}
