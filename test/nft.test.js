const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("NFTModule", function () {
  let deployer, user1, user2, multisig;
  let token, treasury, nftMinting, royaltyManager, boostEngine;
  let startTimestamp;

  beforeEach(async () => {
    [deployer, user1, user2, multisig] = await ethers.getSigners();

    // Deploy MFHToken with zero address as trusted forwarder for testing
    const MFHToken = await ethers.getContractFactory("MFHToken");
    token = await MFHToken.deploy(ethers.ZeroAddress);
    await token.waitForDeployment();

    // Deploy TreasuryVault
    const TreasuryVault = await ethers.getContractFactory("TreasuryVault");
    treasury = await TreasuryVault.deploy(multisig.address);
    await treasury.waitForDeployment();

    // Deploy NFTMinting
    const NFTMinting = await ethers.getContractFactory("NFTMinting");
    nftMinting = await NFTMinting.deploy(token.target);
    await nftMinting.waitForDeployment();

    // Deploy RoyaltyManager
    const RoyaltyManager = await ethers.getContractFactory("RoyaltyManager");
    royaltyManager = await RoyaltyManager.deploy(token.target, treasury.target);
    await royaltyManager.waitForDeployment();

    // Deploy BoostEngine
    const BoostEngine = await ethers.getContractFactory("BoostEngine");
    boostEngine = await BoostEngine.deploy(token.target, treasury.target);
    await boostEngine.waitForDeployment();

    // Transfer tokens to users for minting and boosting
    await token.transfer(user1.address, ethers.parseEther("1000"));
    await token.transfer(user2.address, ethers.parseEther("500"));

    // Set starting timestamp
    startTimestamp = (await ethers.provider.getBlock("latest")).timestamp + 100;
    await network.provider.send("evm_setNextBlockTimestamp", [startTimestamp]);
    await network.provider.send("evm_mine");
  });

  describe("NFTMinting.sol", function () {
    it("should mint NFT with valid metadata and payment", async () => {
      await token.connect(user1).approve(nftMinting.target, ethers.parseEther("10"));
      const metadataURI = "ipfs://test-metadata";
      await expect(nftMinting.connect(user1).mintNFT(metadataURI))
        .to.emit(nftMinting, "NFTMinted")
        .withArgs(user1.address, 1);

      expect(await nftMinting.ownerOf(1)).to.equal(user1.address);
      expect(await nftMinting.tokenURI(1)).to.equal(metadataURI);
      expect(await nftMinting.mintedBy(user1.address)).to.equal(1);
      expect(await token.balanceOf(nftMinting.target)).to.equal(ethers.parseEther("10"));
    });

    it("should reject minting with invalid metadata", async () => {
      await token.connect(user1).approve(nftMinting.target, ethers.parseEther("10"));
      await expect(nftMinting.connect(user1).mintNFT(""))
        .to.be.revertedWith("Invalid metadata URI");
    });

    it("should reject minting beyond max per wallet", async () => {
      await token.connect(user1).approve(nftMinting.target, ethers.parseEther("50"));
      const metadataURI = "ipfs://test-metadata";
      for (let i = 0; i < 5; i++) {
        await nftMinting.connect(user1).mintNFT(metadataURI);
      }
      await expect(nftMinting.connect(user1).mintNFT(metadataURI))
        .to.be.revertedWith("Mint limit exceeded");
    });

    it("should fail if allowance is insufficient", async () => {
      await token.connect(user1).approve(nftMinting.target, ethers.parseEther("5")); // less than mintPrice
      await expect(nftMinting.connect(user1).mintNFT("ipfs://fail-test"))
        .to.be.revertedWith("ERC20: insufficient allowance");
    });

    it("should allow owner to set mint price and withdraw fees", async () => {
      await token.connect(user1).approve(nftMinting.target, ethers.parseEther("10"));
      await nftMinting.connect(user1).mintNFT("ipfs://test-metadata");

      await nftMinting.setMintPrice(ethers.parseEther("20"));
      expect(await nftMinting.mintPrice()).to.equal(ethers.parseEther("20"));

      const initialBalance = await token.balanceOf(deployer.address);
      await nftMinting.withdrawFees(deployer.address);
      const finalBalance = await token.balanceOf(deployer.address);
      expect(BigInt(finalBalance) - BigInt(initialBalance)).to.equal(ethers.parseEther("10"));
    });
  });

  describe("RoyaltyManager.sol", function () {
    it("should set royalty for a token", async () => {
      await expect(royaltyManager.setRoyalty(1, user1.address, 500))
        .to.emit(royaltyManager, "RoyaltySet")
        .withArgs(1, user1.address, 500);

      const royalty = await royaltyManager.royalties(1);
      expect(royalty.percent).to.equal(500);
      expect(royalty.creator).to.equal(user1.address);
    });

    it("should reject royalty above max (10%)", async () => {
      await expect(royaltyManager.setRoyalty(1, user1.address, 1001))
        .to.be.revertedWith("Royalty too high");
    });

    it("should distribute royalty correctly via contract", async () => {
      await royaltyManager.setRoyalty(1, user1.address, 500); // 5%
      const salePrice = ethers.parseEther("100");

      // Get initial balances
      const initialCreatorBalance = await token.balanceOf(user1.address);
      const initialTreasuryBalance = await token.balanceOf(treasury.target);

      await token.connect(user2).approve(royaltyManager.target, salePrice);

      await expect(royaltyManager.connect(user2).distributeRoyaltyFromContract(1, salePrice))
        .to.emit(royaltyManager, "RoyaltyPaid");

      const royaltyAmount = (salePrice * 500n) / 10000n; // 5% of sale price
      const platformAmount = (royaltyAmount * 200n) / 10000n; // 2% of royalty
      const creatorAmount = royaltyAmount - platformAmount;

      // Check balance changes
      expect(await token.balanceOf(user1.address)).to.equal(initialCreatorBalance + creatorAmount);
      expect(await token.balanceOf(treasury.target)).to.equal(initialTreasuryBalance + platformAmount);
    });

    it("should not revert if no royalty set", async () => {
      const salePrice = ethers.parseEther("50");
      await token.connect(user2).approve(royaltyManager.target, salePrice);
      await expect(royaltyManager.connect(user2).distributeRoyaltyFromContract(999, salePrice))
        .to.not.be.reverted;
    });

    it("should allow owner to set platform cut and treasury", async () => {
      await royaltyManager.setPlatformCut(300); // 3%
      expect(await royaltyManager.platformCut()).to.equal(300);

      await royaltyManager.setTreasury(user2.address);
      expect(await royaltyManager.platformTreasury()).to.equal(user2.address);
    });
  });

  describe("BoostEngine.sol", function () {
    it("should boost NFT with valid duration and payment", async () => {
      await token.connect(user1).approve(boostEngine.target, ethers.parseEther("5"));
      await network.provider.send("evm_setNextBlockTimestamp", [startTimestamp + 100]);
      const boostTimestamp = startTimestamp + 100;
      const expectedEnd = boostTimestamp + 1 * 86400;

      await expect(boostEngine.connect(user1).boostNFT(1, 1))
        .to.emit(boostEngine, "NFTBoosted")
        .withArgs(1, user1.address, 1, expectedEnd);

      const boostEnd = await boostEngine.boostedUntil(1);
      expect(boostEnd).to.equal(expectedEnd);
      expect(await boostEngine.isBoosted(1)).to.be.true;
      expect(await token.balanceOf(treasury.target)).to.equal(ethers.parseEther("5"));
    });

    it("should extend existing boost", async () => {
      await token.connect(user1).approve(boostEngine.target, ethers.parseEther("15"));
      await boostEngine.connect(user1).boostNFT(1, 1); // 1 day
      const initialBoostEnd = await boostEngine.boostedUntil(1);

      await network.provider.send("evm_setNextBlockTimestamp", [startTimestamp + 3600]);
      await boostEngine.connect(user1).boostNFT(1, 2); // add 2 days
      const newBoostEnd = await boostEngine.boostedUntil(1);

      expect(newBoostEnd).to.equal(BigInt(initialBoostEnd) + 2n * 86400n);
    });

    it("should reject boost with zero duration", async () => {
      await token.connect(user1).approve(boostEngine.target, ethers.parseEther("5"));
      await expect(boostEngine.connect(user1).boostNFT(1, 0))
        .to.be.revertedWith("Invalid boost period");
    });

    it("should reject boost if treasury not set", async () => {
      const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
      await boostEngine.setTreasury(ZERO_ADDRESS);
      await token.connect(user1).approve(boostEngine.target, ethers.parseEther("5"));
      await expect(boostEngine.connect(user1).boostNFT(1, 1))
        .to.be.revertedWith("Treasury not set");
    });

    it("should allow owner to set boost rate and treasury", async () => {
      await boostEngine.setBoostFeePerDay(ethers.parseEther("10"));
      expect(await boostEngine.boostFeePerDay()).to.equal(ethers.parseEther("10"));

      await boostEngine.setTreasury(user2.address);
      expect(await boostEngine.treasury()).to.equal(user2.address);
    });

    it("should correctly handle boost expiration", async () => {
      await token.connect(user1).approve(boostEngine.target, ethers.parseEther("5"));
      await boostEngine.connect(user1).boostNFT(1, 1);

      await network.provider.send("evm_setNextBlockTimestamp", [startTimestamp + 2 * 86400]);
      await network.provider.send("evm_mine");

      expect(await boostEngine.isBoosted(1)).to.be.false;
    });

    it("should correctly stack multiple boosts", async () => {
      await token.connect(user1).approve(boostEngine.target, ethers.parseEther("20"));
      await boostEngine.connect(user1).boostNFT(1, 1); // 1 day
      const firstEnd = await boostEngine.boostedUntil(1);

      await boostEngine.connect(user1).boostNFT(1, 2); // add 2 days
      const secondEnd = await boostEngine.boostedUntil(1);

      expect(secondEnd).to.equal(BigInt(firstEnd) + 2n * 86400n);
    });
  });
});
