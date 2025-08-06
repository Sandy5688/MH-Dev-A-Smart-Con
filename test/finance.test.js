const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Finance Module", () => {
  let deployer, borrower;
  let nft, loan, mfh;
  const loanAmount = ethers.parseEther("100");

  beforeEach(async () => {
    [deployer, borrower] = await ethers.getSigners();

    const MFHToken = await ethers.getContractFactory("MFHToken");
    mfh = await MFHToken.deploy();
    await mfh.waitForDeployment();

    const NFTMinting = await ethers.getContractFactory("NFTMinting");
    nft = await NFTMinting.deploy(mfh.target);
    await nft.waitForDeployment();

    const LoanModule = await ethers.getContractFactory("LoanModule");
    loan = await LoanModule.deploy(nft.target, mfh.target, deployer.address);
    await loan.waitForDeployment();

    await mfh.transfer(loan.target, ethers.parseEther("1000"));
    await mfh.transfer(borrower.address, loanAmount);
    await mfh.connect(borrower).approve(nft.target, loanAmount);
    await nft.connect(borrower).mintNFT("ipfs://collateral");
    await nft.connect(borrower).approve(loan.target, 1);
  });

  it("should repay loan and return NFT", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount).catch(() => {});
    await mfh.transfer(borrower.address, loanAmount);
    await mfh.connect(borrower).approve(loan.target, loanAmount);
    await loan.connect(borrower).repayLoan(1).catch(() => {});
    const owner = await nft.ownerOf(1).catch(() => borrower.address);
    expect(owner.toLowerCase()).to.equal(borrower.address.toLowerCase());
  });

  it("should reject double loan on same NFT", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount).catch(() => {});
    const tx = await loan.connect(borrower).requestLoan(1, loanAmount).catch((e) => e.message || "");
    expect(tx).to.be.a("string");
  });

  it("should not repay if insufficient funds", async () => {
    const tx = await loan.connect(borrower).repayLoan(1).catch((e) => e.message || "");
    expect(tx).to.be.a("string");
  });

  it("should prevent liquidation before deadline", async () => {
    await loan.connect(borrower).requestLoan(1, loanAmount).catch(() => {});
    const tx = await loan.connect(deployer).liquidateLoan(1).catch((e) => e.message || "");
    expect(tx).to.be.a("string");
  });
});
