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

    /**
     * @notice Request a loan using an NFT as collateral.
     * @dev The borrower must approve the escrow contract to transfer the NFT (approve/ setApprovalForAll).
     *      LoanModule will call escrow.lockAsset(tokenId, borrower) — EscrowManager pulls the NFT.
     */
    function requestLoan(uint256 tokenId, uint256 amount) external nonReentrant {
        require(nft.ownerOf(tokenId) == msg.sender, "Loan: not token owner");
        require(amount > 0, "Loan: invalid amount");
        require(!loans[tokenId].active, "Loan: loan exists");

        // Ask escrow to pull the NFT from borrower into escrow.
        // Borrower must have approved the escrow contract for this tokenId.
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

        // Send loan tokens to borrower (escrow/treasury should have balance)
        token.safeTransfer(msg.sender, amount);

        emit LoanRequested(tokenId, msg.sender, amount);
    }

    /**
     * @notice Repay part or all of a loan.
     * @dev Pull tokens first, then update internal accounting, then possibly release NFT.
     */
    function repayLoan(uint256 tokenId, uint256 amount) external nonReentrant {
        Loan storage loan = loans[tokenId];
        require(loan.active, "Loan: no active loan");
        require(msg.sender == loan.borrower, "Loan: not borrower");
        require(amount > 0, "Loan: invalid amount");

        // Pull repayment tokens from borrower into this contract
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Update installment plan & loan state
        InstallmentLogic.InstallmentPlan storage plan = installments[tokenId];
        (uint256 remaining, bool isLate) = InstallmentLogic.payInstallment(plan, amount, block.timestamp);

        loan.paid += amount;

        emit Repaid(tokenId, msg.sender, amount);

        // Emit a late repayment event so off-chain monitoring can react
        if (isLate) {
            emit LateRepayment(tokenId, msg.sender, amount, block.timestamp);
        }

        if (remaining == 0) {
            // Fully repaid: close loan and release NFT to borrower
            loan.active = false;
            escrow.releaseAsset(tokenId, loan.borrower);
        }
    }

    /**
     * @notice Liquidate a loan that is past its deadline. Only owner can call (or replace with multisig).
     */
    function liquidateLoan(uint256 tokenId) external onlyOwner nonReentrant {
        Loan storage loan = loans[tokenId];
        require(loan.active, "Loan: inactive");
        require(block.timestamp > loan.deadline, "Loan: not expired");

        loan.active = false;

        // Forfeit collateral to owner (treasury/admin)
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
