// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./InstallmentLogic.sol";

interface IEscrowManager {
    function lockAsset(uint256 tokenId, address depositor) external;
    function releaseAsset(uint256 tokenId, address to) external;
    function forfeitAsset(uint256 tokenId, address to) external;
}

contract LoanModule is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC721 public nft;
    IERC20 public token;
    IEscrowManager public escrow;

    struct Loan {
        address borrower;
        uint256 amount;
        uint256 paid;
        uint256 createdAt;
        uint256 deadline;
        bool active;
    }

    mapping(uint256 => Loan) public loans;
    mapping(uint256 => InstallmentLogic.InstallmentPlan) public installments;

    uint256 public loanDuration = 30 days;
    uint8 public maxInstallments = 4;

    event LoanRequested(uint256 indexed tokenId, address indexed borrower, uint256 amount);
    event Repaid(uint256 indexed tokenId, address indexed borrower, uint256 amount);
    event LateRepayment(uint256 indexed tokenId, address indexed borrower, uint256 amount, uint256 timestamp);
    event Liquidated(uint256 indexed tokenId, address indexed liquidator);
    event WithdrawalBlocked(uint256 indexed tokenId, address indexed borrower, uint256 timestamp);

    constructor(address _nft, address _token, address _escrow) {
        require(_nft != address(0) && _token != address(0) && _escrow != address(0), "Invalid addresses");
        nft = IERC721(_nft);
        token = IERC20(_token);
        escrow = IEscrowManager(_escrow);
    }

    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
    }

    modifier onlyBorrower(uint256 tokenId) {
        require(loans[tokenId].borrower == msg.sender, "Loan: not borrower");
        _;
    }

    modifier onlyActiveLoan(uint256 tokenId) {
        require(loans[tokenId].active, "Loan: no active loan");
        _;
    }

    modifier canWithdraw(uint256 tokenId) {
        Loan storage loan = loans[tokenId];
        if (loan.paid < loan.amount) {
            revert("Loan: cannot withdraw before full repayment");
        }
        _;
    }

    function requestLoan(uint256 tokenId, uint256 amount) external nonReentrant {
        require(nft.ownerOf(tokenId) == msg.sender, "Loan: not token owner");
        require(amount > 0, "Loan: invalid amount");
        require(!loans[tokenId].active, "Loan: loan exists");

        // Lock NFT collateral in escrow
        escrow.lockAsset(tokenId, msg.sender);

        loans[tokenId] = Loan({
            borrower: msg.sender,
            amount: amount,
            paid: 0,
            createdAt: block.timestamp,
            deadline: block.timestamp + loanDuration,
            active: true
        });

        installments[tokenId] = InstallmentLogic.createPlan(amount, maxInstallments);

        // Transfer loan amount to borrower
        token.safeTransfer(msg.sender, amount);

        emit LoanRequested(tokenId, msg.sender, amount);
    }

    function repayLoan(uint256 tokenId, uint256 amount) external onlyBorrower(tokenId) onlyActiveLoan(tokenId) nonReentrant {
        require(amount > 0, "Loan: invalid amount");

        Loan storage loan = loans[tokenId];

        // Prevent overpayment
        uint256 remaining = loan.amount - loan.paid;
        if (amount > remaining) {
            amount = remaining;
        }

        // Pull repayment tokens
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Update installment plan
        InstallmentLogic.InstallmentPlan storage plan = installments[tokenId];
        (uint256 newRemaining, bool isLate) = InstallmentLogic.payInstallment(plan, amount, block.timestamp);
        
        loan.paid += amount;

        emit Repaid(tokenId, msg.sender, amount);

        if (isLate) {
            emit LateRepayment(tokenId, msg.sender, amount, block.timestamp);
        }

        // If fully repaid, release NFT
        if (loan.paid >= loan.amount) {
            loan.active = false;
            escrow.releaseAsset(tokenId, loan.borrower);
        }
    }

    function withdrawCollateral(uint256 tokenId, address to) external onlyBorrower(tokenId) canWithdraw(tokenId) nonReentrant {
        // Allow borrower to withdraw NFT only after full repayment
        escrow.releaseAsset(tokenId, to);
    }

    function liquidateLoan(uint256 tokenId) external onlyOwner nonReentrant onlyActiveLoan(tokenId) {
        Loan storage loan = loans[tokenId];
        require(block.timestamp > loan.deadline, "Loan: not expired");

        loan.active = false;

        // Forfeit NFT collateral to owner/treasury
        escrow.forfeitAsset(tokenId, owner());

        emit Liquidated(tokenId, msg.sender);
    }

    function getInstallmentStatus(uint256 tokenId) external view returns (uint256 remaining, bool defaulted) {
        return InstallmentLogic.getStatus(installments[tokenId], block.timestamp);
    }

    function setLoanDuration(uint256 duration) external onlyOwner {
        loanDuration = duration;
    }

    function setMaxInstallments(uint8 num) external onlyOwner {
        maxInstallments = num;
    }
}
