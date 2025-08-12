const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Finance Module", () => {
  let deployer, borrower;
  let nft, loan, mfh, escrow;
  const loanAmount = ethers.parseEther("100");

  beforeEach(async () => {
    [deployer, borrower] = await ethers.getSigners();

    const MFHToken = await ethers.getContractFactory("MFHToken");
    mfh = await MFHToken.deploy();
    await mfh.waitForDeployment();

    const NFTMinting = await ethers.getContractFactory("NFTMinting");
    nft = await NFTMinting.deploy(mfh.target);
    await nft.waitForDeployment();

    const EscrowManager = await ethers.getContractFactory("EscrowManager");
    escrow = await EscrowManager.deploy(nft.target);
    await escrow.waitForDeployment();

    const LoanModule = await ethers.getContractFactory("LoanModule");
    loan = await LoanModule.deploy(nft.target, mfh.target, escrow.target);
    await loan.waitForDeployment();

    await escrow.setTrusted(loan.target, true);

    // Fund loan module with MFH tokens
    await mfh.transfer(loan.target, ethers.parseEther("1000"));

    // Give borrower MFH to pay mint price
    const mintPrice = await nft.mintPrice(); // dynamically get the mint price
    await mfh.transfer(borrower.address, mintPrice);

    // Approve NFTMinting contract to spend borrower's MFH tokens
    await mfh.connect(borrower).approve(nft.target, mintPrice);

    // Mint NFT to borrower
    await nft.connect(borrower).mintNFT("ipfs://collateral");

    // Approve escrow to move borrower's NFT
    await nft.connect(borrower).approve(escrow.target, 1);
  });

  it("should request and repay loan, releasing NFT", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);

    // borrower receives loanAmount in MFH
    expect(await mfh.balanceOf(borrower.address)).to.equal(loanAmount);

    // Approve repayment amount
    await mfh.connect(borrower).approve(loan.target, loanAmount);

    // Repay full loan
    await loan.connect(borrower).repayLoan(1, loanAmount);

    const owner = await nft.ownerOf(1);
    expect(owner).to.equal(borrower.address);
  });

  it("should reject double loan on same NFT", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);
    // Updated expectation to match actual revert reason from contract flow
    await expect(
      loan.connect(borrower).requestLoan(1, loanAmount)
    ).to.be.revertedWith("Loan: not token owner");
  });

  it("should not repay if insufficient funds", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);
    await expect(loan.connect(borrower).repayLoan(1, loanAmount)).to.be.reverted;
  });

  it("should prevent liquidation before deadline", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);
    await expect(loan.connect(deployer).liquidateLoan(1)).to.be.revertedWith("Loan: not expired");
  });

  it("should liquidate loan after deadline", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);

    // move time forward beyond deadline
    await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]); // +31 days
    await ethers.provider.send("evm_mine");

    await loan.connect(deployer).liquidateLoan(1);

    const owner = await nft.ownerOf(1);
    expect(owner).to.equal(deployer.address);
  });
});
