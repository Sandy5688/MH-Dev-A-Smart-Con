const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NFT Rental System", function () {
  let NFTMinting, RentalEngine, LeaseAgreement;
  let nft, rentalEngine, leaseAgreement;
  let owner, lessor, lessee, treasury;
  const TOKEN_ID = 1;
  const DURATION = 86400; // 1 day

  beforeEach(async function () {
    [owner, lessor, lessee, treasury] = await ethers.getSigners();

    const MFHToken = await ethers.getContractFactory("MFHToken");
    const mfh = await MFHToken.deploy();
    await mfh.waitForDeployment();

    NFTMinting = await ethers.getContractFactory("NFTMinting");
    nft = await NFTMinting.deploy(mfh.target);
    await nft.waitForDeployment();

    // Fund lessor with minting tokens
    await mfh.transfer(lessor.address, ethers.parseEther("100"));
    await mfh.connect(lessor).approve(nft.target, ethers.parseEther("100"));

    // Mint NFT to lessor
    await nft.connect(lessor).mintNFT("ipfs://test-uri");

    RentalEngine = await ethers.getContractFactory("RentalEngine");
    rentalEngine = await RentalEngine.deploy(nft.target);
    await rentalEngine.waitForDeployment();

    LeaseAgreement = await ethers.getContractFactory("LeaseAgreement");
    leaseAgreement = await LeaseAgreement.deploy(nft.target, rentalEngine.target);
    await leaseAgreement.waitForDeployment();

    await rentalEngine.setTreasury(treasury.address);
  });

  describe("RentalEngine", function () {
    it("should set treasury correctly", async function () {
      expect(await rentalEngine.treasury()).to.equal(treasury.address);
    });

    it("should fail to set zero address as treasury", async function () {
      await expect(rentalEngine.setTreasury(ethers.ZeroAddress))
        .to.be.revertedWith("Invalid treasury");
    });
  });

  describe("LeaseAgreement", function () {
    it("should fail if non-owner tries lease", async function () {
      await expect(
        leaseAgreement.connect(lessee).startLease(TOKEN_ID, lessee.address, DURATION)
      ).to.be.revertedWith("Not token owner");
    });
  });
});
