const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log, getOrNull } = deployments;
  const { deployer } = await getNamedAccounts();

  log(" Deploying Marketplace Module...");

  const paymentToken = (await deployments.get("MFHToken")).address;
  const nft = (await deployments.get("NFTMinting")).address;
  const royaltyManager = (await deployments.get("RoyaltyManager")).address;
  const treasury = process.env.TREASURY_ADDRESS || deployer;
  const escrow = (await getOrNull("EscrowManager"))?.address || "0x0000000000000000000000000000000000000000";

  // 1. MarketplaceCore
  const existingCore = await getOrNull("MarketplaceCore");
  if (!existingCore) {
    const core = await deploy("MarketplaceCore", {
      from: deployer,
      args: [nft, paymentToken, treasury, royaltyManager],
      log: true,
    });
    log(` MarketplaceCore at ${core.address} | Gas: ${core.receipt.gasUsed}`);
  } else {
    log(` MarketplaceCore already deployed at ${existingCore.address}`);
  }

  // 2. BuyNowPayLater
  const existingBNPL = await getOrNull("BuyNowPayLater");
  if (!existingBNPL) {
    const bnpl = await deploy("BuyNowPayLater", {
      from: deployer,
      args: [nft, paymentToken, escrow],
      log: true,
    });
    log(` BuyNowPayLater at ${bnpl.address} | Gas: ${bnpl.receipt.gasUsed}`);
  } else {
    log(` BuyNowPayLater already deployed at ${existingBNPL.address}`);
  }

  // 3. AuctionModule
  const existingAuction = await getOrNull("AuctionModule");
  if (!existingAuction) {
    const auction = await deploy("AuctionModule", {
      from: deployer,
      args: [nft, paymentToken],
      log: true,
    });
    log(` AuctionModule at ${auction.address} | Gas: ${auction.receipt.gasUsed}`);
  } else {
    log(` AuctionModule already deployed at ${existingAuction.address}`);
  }

  // 4. BiddingSystem
  const existingBidding = await getOrNull("BiddingSystem");
  if (!existingBidding) {
    const bidding = await deploy("BiddingSystem", {
      from: deployer,
      args: [nft, paymentToken],
      log: true,
    });
    log(` BiddingSystem at ${bidding.address} | Gas: ${bidding.receipt.gasUsed}`);
  } else {
    log(` BiddingSystem already deployed at ${existingBidding.address}`);
  }

  log(" Marketplace Module deployed.");
};

module.exports.tags = ["MarketplaceModule"];
