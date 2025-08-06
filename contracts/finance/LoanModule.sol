// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./InstallmentLogic.sol";

interface IEscrowManager {
    function lockAsset(address nft, uint256 tokenId) external;
    function releaseAsset(address nft, uint256 tokenId, address to) external;
    function forfeitAsset(address nft, uint256 tokenId, address to) external;
}

contract LoanModule is Ownable {
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

    event LoanRequested(uint256 tokenId, address borrower, uint256 amount);
    event Repaid(uint256 tokenId, address borrower, uint256 amount);
    event Liquidated(uint256 tokenId, address liquidator);

    constructor(address _nft, address _token, address _escrow) {
        nft = IERC721(_nft);
        token = IERC20(_token);
        escrow = IEscrowManager(_escrow);
    }

    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
    }

    function requestLoan(uint256 tokenId, uint256 amount) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(amount > 0, "Invalid amount");
        require(!loans[tokenId].active, "Loan exists");

        // Lock NFT into escrow
        nft.transferFrom(msg.sender, address(escrow), tokenId);
        escrow.lockAsset(address(nft), tokenId);

        loans[tokenId] = Loan({
            borrower: msg.sender,
            amount: amount,
            paid: 0,
            createdAt: block.timestamp,
            deadline: block.timestamp + loanDuration,
            active: true
        });

        installments[tokenId] = InstallmentLogic.createPlan(amount, maxInstallments);

        // Send loan tokens to borrower
        token.transfer(msg.sender, amount);

        emit LoanRequested(tokenId, msg.sender, amount);
    }

    function repayLoan(uint256 tokenId, uint256 amount) external {
        Loan storage loan = loans[tokenId];
        require(loan.active, "No active loan");
        require(msg.sender == loan.borrower, "Not borrower");

        InstallmentLogic.InstallmentPlan storage plan = installments[tokenId];
        (uint256 remaining, bool isLate) = InstallmentLogic.payInstallment(plan, amount, block.timestamp);

        loan.paid += amount;

        token.transferFrom(msg.sender, address(this), amount);
        emit Repaid(tokenId, msg.sender, amount);

        if (remaining == 0) {
            loan.active = false;
            escrow.releaseAsset(address(nft), tokenId, loan.borrower);
        }
    }

    function liquidateLoan(uint256 tokenId) external onlyOwner {
        Loan storage loan = loans[tokenId];
        require(loan.active, "Loan inactive");
        require(block.timestamp > loan.deadline, "Loan not expired");

        loan.active = false;
        escrow.forfeitAsset(address(nft), tokenId, owner());

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
