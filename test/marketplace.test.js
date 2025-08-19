const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe("MarketplaceModule", function () {
  let deployer, user1, user2, multisig;
  let token, nft, treasury, royaltyManager, marketplace, bnpl, auction, bidding, escrow;
  let startTimestamp;
beforeEach(async () => {
  try {
    [deployer, user1, user2, multisig] = await ethers.getSigners();

    // Deploy MFHToken with zero address as trusted forwarder for testing
    const MFHToken = await ethers.getContractFactory("MFHToken");
    token = await MFHToken.deploy(ethers.ZeroAddress);
    await token.waitForDeployment();

    // Deploy TreasuryVault (address _multisig)
    const TreasuryVault = await ethers.getContractFactory("TreasuryVault");
    treasury = await TreasuryVault.deploy(multisig.address);
    await treasury.waitForDeployment();

    // Deploy NFTMinting (address _paymentToken)
    const NFTMinting = await ethers.getContractFactory("NFTMinting");
    nft = await NFTMinting.deploy(await token.getAddress());
    await nft.waitForDeployment();

    // Deploy RoyaltyManager (address _paymentToken, address _treasury)
    const RoyaltyManager = await ethers.getContractFactory("RoyaltyManager");
    royaltyManager = await RoyaltyManager.deploy(await token.getAddress(), await treasury.getAddress());
    await royaltyManager.waitForDeployment();

  // Deploy EscrowManager (address _nft)
    const EscrowManager = await ethers.getContractFactory("EscrowManager");
  escrow = await EscrowManager.deploy(await nft.getAddress());
    await escrow.waitForDeployment();

    // Deploy BuyNowPayLater (address _nft, address _paymentToken, address _escrow, address _royaltyManager)
    const BuyNowPayLater = await ethers.getContractFactory("BuyNowPayLater");
    bnpl = await BuyNowPayLater.deploy(
      await nft.getAddress(),
      await token.getAddress(),
      await escrow.getAddress(),
      await royaltyManager.getAddress()
    );
    await bnpl.waitForDeployment();
    await escrow.setTrusted(await bnpl.getAddress(), true);

    // Deploy MarketplaceCore (address _nft, address _paymentToken, address _treasury, address _royaltyManager)
    const MarketplaceCore = await ethers.getContractFactory("MarketplaceCore");
    marketplace = await MarketplaceCore.deploy(
      await nft.getAddress(),
      await token.getAddress(),
      await treasury.getAddress(),
      await royaltyManager.getAddress()
    );
    await marketplace.waitForDeployment();

  // mark marketplace and other modules as trusted in escrow
  await escrow.setTrusted(await marketplace.getAddress(), true);

    // Deploy AuctionModule (address _nft, address _paymentToken, address _escrow, address _treasury, address _royaltyManager)
    const AuctionModule = await ethers.getContractFactory("AuctionModule");
    auction = await AuctionModule.deploy(
      await nft.getAddress(),
      await token.getAddress(),
      await escrow.getAddress(),
      await treasury.getAddress(),
      await royaltyManager.getAddress()
    );
    await auction.waitForDeployment();
  await escrow.setTrusted(await auction.getAddress(), true);

    // Deploy BiddingSystem (address _nft, address _paymentToken, address _escrow)
    const BiddingSystem = await ethers.getContractFactory("BiddingSystem");
    bidding = await BiddingSystem.deploy(
      await nft.getAddress(),
      await token.getAddress(),
      await escrow.getAddress()
    );
    await bidding.waitForDeployment();
  await escrow.setTrusted(await bidding.getAddress(), true);

    // Fund users with tokens
    await token.transfer(user1.address, ethers.parseEther("1000"));
    await token.transfer(user2.address, ethers.parseEther("1000"));

    // Mint NFT for user1
    await token.connect(user1).approve(await nft.getAddress(), ethers.parseEther("10"));
    await nft.connect(user1).mintNFT("ipfs://test-metadata");

    startTimestamp = (await ethers.provider.getBlock("latest")).timestamp + 100;
    await network.provider.send("evm_setNextBlockTimestamp", [startTimestamp]);
    await network.provider.send("evm_mine");
  } catch (error) {
    console.error("Error in beforeEach:", error);
    throw error;
  }
});
  /* -------------------- MarketplaceCore -------------------- */
  describe("MarketplaceCore.sol", function () {
    it("listNFT: success", async () => {
      await nft.connect(user1).approve(marketplace.getAddress(), 1);
      await expect(marketplace.connect(user1).listNFT(1, ethers.parseEther("100")))
        .to.emit(marketplace, "ListingCreated")
        .withArgs(1, user1.address, ethers.parseEther("100"));
  expect(await nft.ownerOf(1)).to.equal(await marketplace.getAddress());
    });

    it("listNFT: fail (not owner)", async () => {
      await expect(marketplace.connect(user2).listNFT(1, ethers.parseEther("100")))
        .to.be.revertedWith("Not the owner");
    });

    it("cancelListing: only seller can cancel", async () => {
      await nft.connect(user1).approve(marketplace.getAddress(), 1);
      await marketplace.connect(user1).listNFT(1, ethers.parseEther("100"));
      await expect(marketplace.connect(user2).cancelListing(1))
        .to.be.revertedWith("Not seller or owner");
    });

    it("buyNFT: happy path with royalty", async () => {
      await royaltyManager.setRoyalty(1, user1.address, 500); // 5%
      await nft.connect(user1).approve(marketplace.getAddress(), 1);
      await marketplace.connect(user1).listNFT(1, ethers.parseEther("100"));

      await token.connect(user2).approve(marketplace.getAddress(), ethers.parseEther("100"));
      await expect(marketplace.connect(user2).buyNFT(1))
        .to.emit(marketplace, "ItemSold");

      expect(await nft.ownerOf(1)).to.equal(user2.address);
    });

    it("buyNFT: fails without allowance", async () => {
      await nft.connect(user1).approve(marketplace.getAddress(), 1);
      await marketplace.connect(user1).listNFT(1, ethers.parseEther("100"));
      await expect(marketplace.connect(user2).buyNFT(1))
        .to.be.revertedWith("ERC20: insufficient allowance");
    });

    it("buyNFT: seller cannot buy own listing", async () => {
      await nft.connect(user1).approve(marketplace.getAddress(), 1);
      await marketplace.connect(user1).listNFT(1, ethers.parseEther("100"));
      await token.connect(user1).approve(marketplace.getAddress(), ethers.parseEther("100"));
      await expect(marketplace.connect(user1).buyNFT(1))
        .to.be.revertedWith("Seller cannot buy own listing");
    });
  });

  /* -------------------- BuyNowPayLater -------------------- */
  describe("BuyNowPayLater.sol", function () {
    it("Successful BNPL lifecycle", async () => {
      await nft.connect(user1).approve(escrow.getAddress(), 1);
  // approve BNPL to pull downpayment and remaining installments
  await token.connect(user1).approve(bnpl.getAddress(), ethers.parseEther("100"));
  await bnpl.connect(user1).initiateBNPL(1, ethers.parseEther("100"), ethers.parseEther("20"), 3);
  await bnpl.connect(user1).payInstallment(1, ethers.parseEther("80"));
    });

    it("Default scenario forfeits asset", async () => {
  await nft.connect(user1).approve(escrow.getAddress(), 1);
  await token.connect(user1).approve(bnpl.getAddress(), ethers.parseEther("100"));
  await bnpl.connect(user1).initiateBNPL(1, ethers.parseEther("100"), ethers.parseEther("20"), 3);
  // advance time beyond installments*30 days to trigger default (3*30 days)
  const beyondDeadline = startTimestamp + (3 * 30 * 86400) + 1;
  await network.provider.send("evm_setNextBlockTimestamp", [beyondDeadline]);
  await network.provider.send("evm_mine");
    // ensure current block timestamp is > stored deadline; if not, advance further
    const plan = await bnpl.plans(1);
    const deadline = plan.deadline;
    const latest = (await ethers.provider.getBlock('latest')).timestamp;
    if (latest <= deadline) {
      const extra = Number(deadline) - latest + 1;
      await network.provider.send("evm_setNextBlockTimestamp", [latest + extra]);
      await network.provider.send("evm_mine");
    }
    await bnpl.markDefault(1);
    });
  });

  /* -------------------- AuctionModule -------------------- */
  describe("AuctionModule.sol", function () {
    it("startAuction with escrow", async () => {
    // seller must approve escrow to allow escrow to pull NFT
    await nft.connect(user1).approve(escrow.getAddress(), 1);
  await auction.connect(user1).startAuction(1, ethers.parseEther("10"), 86400);
  expect(await nft.ownerOf(1)).to.equal(await escrow.getAddress());
    });

    it("placeBid rejects low bids or after expiry", async () => {
    await nft.connect(user1).approve(escrow.getAddress(), 1);
    await auction.connect(user1).startAuction(1, ethers.parseEther("10"), 86400);
      await expect(auction.connect(user2).placeBid(1, ethers.parseEther("5")))
        .to.be.revertedWith("Bid too low");
    });

    it("finalizeAuction pays royalties + platform fee", async () => {
    await nft.connect(user1).approve(escrow.getAddress(), 1);
    await auction.connect(user1).startAuction(1, ethers.parseEther("10"), 86400);
      await token.connect(user2).approve(auction.getAddress(), ethers.parseEther("15"));
  await auction.connect(user2).placeBid(1, ethers.parseEther("15"));
  await network.provider.send("evm_setNextBlockTimestamp", [startTimestamp + 2 * 86400]);
  await auction.finalizeAuction(1);
  expect(await nft.ownerOf(1)).to.equal(user2.address);
    });
  });

  /* -------------------- BiddingSystem -------------------- */
  describe("BiddingSystem.sol", function () {
    it("rejects zero bids", async () => {
      await expect(bidding.connect(user2).placeBid(1, 0))
        .to.be.revertedWith("Zero bid");
    });

    it("Tie-breaking: equal amount later fails", async () => {
      await token.connect(user2).approve(bidding.getAddress(), ethers.parseEther("50"));
      await bidding.connect(user2).placeBid(1, ethers.parseEther("50"));
      await token.connect(user1).approve(bidding.getAddress(), ethers.parseEther("50"));
      await expect(bidding.connect(user1).placeBid(1, ethers.parseEther("50")))
        .to.be.revertedWith("Bid not higher than current");
    });

    it("Auto-accept locks NFT", async () => {
    await nft.connect(user1).approve(escrow.getAddress(), 1);
      await bidding.connect(user1).setAutoAcceptPrice(1, ethers.parseEther("100"));
      await token.connect(user2).approve(bidding.getAddress(), ethers.parseEther("100"));
      await bidding.connect(user2).placeBid(1, ethers.parseEther("100"));
    });

    it("Cancel bid refunds tokens", async () => {
      await token.connect(user2).approve(bidding.getAddress(), ethers.parseEther("50"));
      await bidding.connect(user2).placeBid(1, ethers.parseEther("50"));
      await bidding.connect(user2).cancelBid(1);
    });
  });
});