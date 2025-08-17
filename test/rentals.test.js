const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RentalsModule", function () {
  let NFTMinting, RentalEngine, LeaseAgreement;
  let nft, rentalEngine, leaseAgreement;
  let owner, lessor, lessee, treasury, other;
  const TOKEN_ID = 1;
  const DURATION = 86400; // 1 day

  beforeEach(async function () {
    [owner, lessor, lessee, treasury, other] = await ethers.getSigners();

    // Deploy MFHToken for minting payments
    const MFHToken = await ethers.getContractFactory("MFHToken");
    const mfh = await MFHToken.deploy();
    await mfh.waitForDeployment();

    // Deploy NFTMinting
    NFTMinting = await ethers.getContractFactory("NFTMinting");
    nft = await NFTMinting.deploy(mfh.target);
    await nft.waitForDeployment();

    // Fund lessor
    await mfh.transfer(lessor.address, ethers.parseEther("100"));
    await mfh.connect(lessor).approve(nft.target, ethers.parseEther("100"));

    // Mint NFT to lessor
    await nft.connect(lessor).mintNFT("ipfs://test-uri");

    // Deploy RentalEngine
    RentalEngine = await ethers.getContractFactory("RentalEngine");
    rentalEngine = await RentalEngine.deploy(nft.target);
    await rentalEngine.waitForDeployment();
    await rentalEngine.setTreasury(treasury.address);

    // Deploy LeaseAgreement
    LeaseAgreement = await ethers.getContractFactory("LeaseAgreement");
    leaseAgreement = await LeaseAgreement.deploy(nft.target, rentalEngine.target);
    await leaseAgreement.waitForDeployment();

    // Mark LeaseAgreement as a trusted module in RentalEngine
    await rentalEngine.setTrustedModule(leaseAgreement.target, true);
  });

  describe("RentalEngine.sol", function () {
    it("should set treasury correctly", async function () {
      expect(await rentalEngine.treasury()).to.equal(treasury.address);
    });

    it("should revert if treasury is zero address", async function () {
      await expect(rentalEngine.setTreasury(ethers.ZeroAddress))
        .to.be.revertedWith("Invalid treasury");
    });

    it("should reject untrusted caller from registering lease", async function () {
      await expect(
        rentalEngine.registerLease(lessor.address, lessee.address, TOKEN_ID, DURATION)
      ).to.be.reverted; // Only trusted modules should call
    });
  });

  describe("LeaseAgreement.sol", function () {
    it("should fail if non-owner tries to start lease", async function () {
      await expect(
        leaseAgreement.connect(lessee).startLease(TOKEN_ID, lessee.address, DURATION)
      ).to.be.revertedWith("Not token owner");
    });

    it("should start lease correctly", async function () {
      const ownerOfNFT = await nft.ownerOf(TOKEN_ID);
      expect(ownerOfNFT).to.equal(lessor.address);

      // Approve RentalEngine to transfer NFT
      await nft.connect(lessor).approve(rentalEngine.target, TOKEN_ID);

      await expect(leaseAgreement.connect(lessor).startLease(TOKEN_ID, lessee.address, DURATION))
        .to.emit(leaseAgreement, "LeaseStarted")
        .withArgs(lessor.address, lessee.address, TOKEN_ID, DURATION);

      // NFT should be in RentalEngine custody
      expect(await nft.ownerOf(TOKEN_ID)).to.equal(rentalEngine.target);

      // Lease info in engine
      const lease = await rentalEngine.getLeaseInfo(TOKEN_ID);
      expect(lease.lessor).to.equal(lessor.address);
      expect(lease.lessee).to.equal(lessee.address);
      expect(lease.active).to.be.true;
    });

    it("should end lease and return NFT", async function () {
      // Approve RentalEngine to transfer NFT
      await nft.connect(lessor).approve(rentalEngine.target, TOKEN_ID);
      await leaseAgreement.connect(lessor).startLease(TOKEN_ID, lessee.address, DURATION);

      // Advance time past lease duration
      const latestBlock = await ethers.provider.getBlock('latest');
      await network.provider.send("evm_setNextBlockTimestamp", [latestBlock.timestamp + DURATION + 1]);
      await network.provider.send("evm_mine");

      await expect(leaseAgreement.connect(lessor).endLease(TOKEN_ID))
        .to.emit(leaseAgreement, "LeaseEnded")
        .withArgs(TOKEN_ID, lessor.address);

      // NFT returned to lessor
      expect(await nft.ownerOf(TOKEN_ID)).to.equal(lessor.address);

      // Lease inactive
      const lease = await rentalEngine.getLeaseInfo(TOKEN_ID);
      expect(lease.active).to.be.false;
    });

    it("should only allow lessor to end lease", async function () {
      // Approve RentalEngine to transfer NFT
      await nft.connect(lessor).approve(rentalEngine.target, TOKEN_ID);
      await leaseAgreement.connect(lessor).startLease(TOKEN_ID, lessee.address, DURATION);

      // Advance time past lease duration
      const latestBlock = await ethers.provider.getBlock('latest');
      await network.provider.send("evm_setNextBlockTimestamp", [latestBlock.timestamp + DURATION + 1]);
      await network.provider.send("evm_mine");

      // Other users should not be able to end lease
      await expect(leaseAgreement.connect(lessee).endLease(TOKEN_ID))
        .to.be.revertedWith("Not authorized");
      await expect(leaseAgreement.connect(other).endLease(TOKEN_ID))
        .to.be.revertedWith("Not authorized");
    });

    it("should handle forceEndLease safely", async function () {
      // Approve RentalEngine to transfer NFT
      await nft.connect(lessor).approve(rentalEngine.target, TOKEN_ID);
      await leaseAgreement.connect(lessor).startLease(TOKEN_ID, lessee.address, DURATION);

      await rentalEngine.forceEndLease(TOKEN_ID);

      // NFT returned
      expect(await nft.ownerOf(TOKEN_ID)).to.equal(lessor.address);

      // Lease removed
      const lease = await rentalEngine.getLeaseInfo(TOKEN_ID);
      expect(lease.active).to.be.false;
    });

    it("should revert if lease duration too short", async function () {
      await expect(
        leaseAgreement.connect(lessor).startLease(TOKEN_ID, lessee.address, 0)
      ).to.be.revertedWith("Min duration is 1 day");
    });
  });

  describe("NFT custody & events", function () {
    it("should keep NFT in engine during lease and emit events", async function () {
      // Approve RentalEngine to transfer NFT
      await nft.connect(lessor).approve(rentalEngine.target, TOKEN_ID);
      await expect(leaseAgreement.connect(lessor).startLease(TOKEN_ID, lessee.address, DURATION))
        .to.emit(leaseAgreement, "LeaseStarted");

      expect(await nft.ownerOf(TOKEN_ID)).to.equal(rentalEngine.target);

      // Advance time past lease duration
      const latestBlock = await ethers.provider.getBlock('latest');
      await network.provider.send("evm_setNextBlockTimestamp", [latestBlock.timestamp + DURATION + 1]);
      await network.provider.send("evm_mine");

      await expect(leaseAgreement.connect(lessor).endLease(TOKEN_ID))
        .to.emit(leaseAgreement, "LeaseEnded");

      expect(await nft.ownerOf(TOKEN_ID)).to.equal(lessor.address);
    });
  });
});
