const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe(" Marketplace Module", function () {
  let deployer, user1, user2, multisig;
  let token, nft, treasury, royaltyManager, marketplace, bnpl, auction, bidding, escrow;
  let startTimestamp;

  beforeEach(async () => {
    [deployer, user1, user2, multisig] = await ethers.getSigners();

    // Deploy MFHToken
    const MFHToken = await ethers.getContractFactory("MFHToken");
    token = await MFHToken.deploy();
    await token.waitForDeployment();
    console.log("MFHToken deployed at:", token.target);

    // Deploy TreasuryVault
    const TreasuryVault = await ethers.getContractFactory("TreasuryVault");
    treasury = await TreasuryVault.deploy(multisig.address);
    await treasury.waitForDeployment();
    console.log("TreasuryVault deployed at:", treasury.target);

    // Deploy NFTMinting
    const NFTMinting = await ethers.getContractFactory("NFTMinting");
    nft = await NFTMinting.deploy(token.target);
    await nft.waitForDeployment();
    console.log("NFTMinting deployed at:", nft.target);

    // Deploy RoyaltyManager
    const RoyaltyManager = await ethers.getContractFactory("RoyaltyManager");
    royaltyManager = await RoyaltyManager.deploy(token.target, treasury.target);
    await royaltyManager.waitForDeployment();
    console.log("RoyaltyManager deployed at:", royaltyManager.target);

    // Deploy EscrowManager
    const EscrowManager = await ethers.getContractFactory("EscrowManager");
    escrow = await EscrowManager.deploy(nft.target);
    await escrow.waitForDeployment();
    console.log("EscrowManager deployed at:", escrow.target);

    // Deploy BuyNowPayLater
    try {
      const BuyNowPayLater = await ethers.getContractFactory("BuyNowPayLater");
      bnpl = await BuyNowPayLater.deploy(nft.target, token.target, escrow.target);
      await bnpl.waitForDeployment();
      console.log("BuyNowPayLater deployed at:", bnpl.target);
    } catch (error) {
      console.error("Failed to deploy BuyNowPayLater:", error);
      throw error;
    }

    // Set BuyNowPayLater as trusted module
    await escrow.setTrusted(bnpl.target, true);
    console.log("BuyNowPayLater set as trusted:", await escrow.trustedModules(bnpl.target));

    // Deploy MarketplaceCore
    const MarketplaceCore = await ethers.getContractFactory("MarketplaceCore");
    marketplace = await MarketplaceCore.deploy(nft.target, token.target, treasury.target, royaltyManager.target);
    await marketplace.waitForDeployment();
    console.log("MarketplaceCore deployed at:", marketplace.target);

    // Deploy AuctionModule
    const AuctionModule = await ethers.getContractFactory("AuctionModule");
    auction = await AuctionModule.deploy(nft.target, token.target);
    await auction.waitForDeployment();
    console.log("AuctionModule deployed at:", auction.target);

    // Deploy BiddingSystem
    const BiddingSystem = await ethers.getContractFactory("BiddingSystem");
    bidding = await BiddingSystem.deploy(nft.target, token.target);
    await bidding.waitForDeployment();
    console.log("BiddingSystem deployed at:", bidding.target);

    // Transfer tokens to users
    await token.transfer(user1.address, ethers.parseEther("1000"));
    await token.transfer(user2.address, ethers.parseEther("1000"));

    // Mint an NFT for user1
    await token.connect(user1).approve(nft.target, ethers.parseEther("10"));
    await nft.connect(user1).mintNFT("ipfs://test-metadata");

    // Set starting timestamp
    startTimestamp = (await ethers.provider.getBlock("latest")).timestamp + 100;
    await network.provider.send("evm_setNextBlockTimestamp", [startTimestamp]);
    await network.provider.send("evm_mine");
  });

  describe(" MarketplaceCore.sol", function () {
    it("should list NFT with valid price and ownership", async () => {
      await nft.connect(user1).approve(marketplace.target, 1);
      await expect(marketplace.connect(user1).listNFT(1, ethers.parseEther("100")))
        .to.emit(marketplace, "NFTListed")
        .withArgs(1, user1.address, ethers.parseEther("100"));
      expect(await nft.ownerOf(1)).to.equal(marketplace.target);
      const listing = await marketplace.listings(1);
      expect(listing.seller).to.equal(user1.address);
      expect(listing.price).to.equal(ethers.parseEther("100"));
    });

    it("should reject listing by non-owner", async () => {
      await expect(marketplace.connect(user2).listNFT(1, ethers.parseEther("100")))
        .to.be.revertedWith("Not the owner");
    });

    it("should allow owner to set platform fee and treasury", async () => {
      await marketplace.setPlatformFee(300); // 3%
      expect(await marketplace.platformFeeBps()).to.equal(300);
      await marketplace.setTreasury(user2.address);
      expect(await marketplace.treasury()).to.equal(user2.address);
    });
  });

  describe(" BuyNowPayLater.sol", function () {
    it("should allow owner to set installment count", async () => {
      await bnpl.setInstallments(4);
      expect(await bnpl.defaultInstallments()).to.equal(4);
    });
  });

  describe(" AuctionModule.sol", function () {
    it("should start auction with valid parameters", async () => {
      await nft.connect(user1).approve(auction.target, 1);
      const duration = 1 * 86400;
      const expectedEndTime = startTimestamp + duration;
      await expect(auction.connect(user1).startAuction(1, ethers.parseEther("10"), duration))
        .to.emit(auction, "AuctionStarted")
        .withArgs(1, ethers.parseEther("10"), (actual) => {
          return actual >= expectedEndTime && actual <= expectedEndTime + 2;
        });
      const auctionData = await auction.auctions(1);
      expect(auctionData.seller).to.equal(user1.address);
      expect(auctionData.minBid).to.equal(ethers.parseEther("10"));
      expect(auctionData.active).to.be.true;
      expect(await nft.ownerOf(1)).to.equal(auction.target);
    });

    it("should allow bidding and refund lower bids", async () => {
      await nft.connect(user1).approve(auction.target, 1);
      await auction.connect(user1).startAuction(1, ethers.parseEther("10"), 1 * 86400);
      await token.connect(user2).approve(auction.target, ethers.parseEther("20"));
      await expect(auction.connect(user2).placeBid(1, ethers.parseEther("15")))
        .to.emit(auction, "BidPlaced")
        .withArgs(1, user2.address, ethers.parseEther("15"));
      const initialBalance = await token.balanceOf(user2.address);
      await token.connect(user2).approve(auction.target, ethers.parseEther("20"));
      await auction.connect(user2).placeBid(1, ethers.parseEther("20"));
      expect(await token.balanceOf(user2.address)).to.equal(
        (BigInt(initialBalance) + BigInt(ethers.parseEther("15")) - BigInt(ethers.parseEther("20"))).toString()
      );
    });

    it("should finalize auction with winner", async () => {
      await nft.connect(user1).approve(auction.target, 1);
      await auction.connect(user1).startAuction(1, ethers.parseEther("10"), 1 * 86400);
      await token.connect(user2).approve(auction.target, ethers.parseEther("15"));
      await auction.connect(user2).placeBid(1, ethers.parseEther("15"));
      await network.provider.send("evm_setNextBlockTimestamp", [startTimestamp + 2 * 86400]);
      await expect(auction.finalizeAuction(1))
        .to.emit(auction, "AuctionEnded")
        .withArgs(1, user2.address, ethers.parseEther("15"));
      expect(await nft.ownerOf(1)).to.equal(user2.address);
      expect(await token.balanceOf(user1.address)).to.equal(
        (BigInt(ethers.parseEther("990")) + BigInt(ethers.parseEther("15"))).toString()
      );
    });

    it("should return NFT if no bids", async () => {
      await nft.connect(user1).approve(auction.target, 1);
      await auction.connect(user1).startAuction(1, ethers.parseEther("10"), 1 * 86400);
      await network.provider.send("evm_setNextBlockTimestamp", [startTimestamp + 2 * 86400]);
      await auction.finalizeAuction(1);
      expect(await nft.ownerOf(1)).to.equal(user1.address);
    });
  });

  describe(" BiddingSystem.sol", function () {
    it("should reject invalid bid cancellation", async () => {
      await expect(bidding.connect(user2).cancelBid(1))
        .to.be.revertedWith("No bid found");
    });

    it("should reject accept bid by non-owner", async () => {
      await token.connect(user2).approve(bidding.target, ethers.parseEther("50"));
      await bidding.connect(user2).placeBid(1, ethers.parseEther("50"));
      await expect(bidding.connect(user2).acceptBid(1, 0))
        .to.be.revertedWith("Not owner");
    });
  });
});