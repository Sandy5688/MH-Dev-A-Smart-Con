const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FinanceModule", () => {
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
    const mintPrice = await nft.mintPrice();
    await mfh.transfer(borrower.address, mintPrice);

    await mfh.connect(borrower).approve(nft.target, mintPrice);
    await nft.connect(borrower).mintNFT("ipfs://collateral");

    await nft.connect(borrower).approve(escrow.target, 1);
  });

  it("should request and repay loan, releasing NFT", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);
    expect(await mfh.balanceOf(borrower.address)).to.equal(loanAmount);

    await mfh.connect(borrower).approve(loan.target, loanAmount);

    await expect(loan.connect(borrower).repayLoan(1, loanAmount))
      .to.emit(loan, "Repaid")
      .withArgs(1, borrower.address, loanAmount);

    const owner = await nft.ownerOf(1);
    expect(owner).to.equal(borrower.address);
  });

  it("should track partial repayments correctly", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);

    await mfh.connect(borrower).approve(loan.target, ethers.parseEther("50"));
    await expect(loan.connect(borrower).repayLoan(1, ethers.parseEther("50")))
      .to.emit(loan, "Repaid")
      .withArgs(1, borrower.address, ethers.parseEther("50"));

    let loanInfo = await loan.loans(1);
    expect(loanInfo.paid).to.equal(ethers.parseEther("50"));
    expect(loanInfo.active).to.equal(true);

    // Repay remaining
    await mfh.connect(borrower).approve(loan.target, ethers.parseEther("50"));
    await loan.connect(borrower).repayLoan(1, ethers.parseEther("50"));

    loanInfo = await loan.loans(1);
    expect(loanInfo.paid).to.equal(ethers.parseEther("100"));
    expect(loanInfo.active).to.equal(false);

    const nftOwner = await nft.ownerOf(1);
    expect(nftOwner).to.equal(borrower.address);
  });

  it("should prevent early withdrawal of collateral", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);

    await expect(loan.connect(borrower).withdrawCollateral(1, borrower.address))
      .to.be.revertedWith("Loan: cannot withdraw before full repayment");
  });

  it("should reject double loan on same NFT", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);
    await expect(loan.connect(borrower).requestLoan(1, loanAmount))
      .to.be.revertedWith("Loan: not token owner");
  });

  it("should prevent repayment without sufficient approved funds", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);
    await expect(loan.connect(borrower).repayLoan(1, loanAmount)).to.be.reverted;
  });

  it("should prevent liquidation before deadline", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);
    await expect(loan.connect(deployer).liquidateLoan(1)).to.be.revertedWith("Loan: not expired");
  });

  it("should liquidate loan after deadline", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount);

    // Move time forward beyond deadline
    await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]); // +31 days
    await ethers.provider.send("evm_mine");

    await expect(loan.connect(deployer).liquidateLoan(1))
      .to.emit(loan, "Liquidated")
      .withArgs(1, deployer.address);

    const owner = await nft.ownerOf(1);
    expect(owner).to.equal(deployer.address);
  });
});
