// deploy/deploy-nft-modules.js
const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log, getOrNull } = deployments;
  const { deployer } = await getNamedAccounts();

  log("\n🔧 Deploying NFT-related Modules...");

  const mfhToken = (await deployments.get("MFHToken")).address;
  const treasury = (process.env.MULTISIG_ADDRESS || deployer);

  // Deploy NFTMinting
  const existingMinting = await getOrNull("NFTMinting");
  if (!existingMinting) {
    const nft = await deploy("NFTMinting", {
      from: deployer,
      args: [mfhToken],
      log: true,
    });
    log(` NFTMinting deployed at ${nft.address} | Gas used: ${nft.receipt.gasUsed}`);
  } else {
    log(` NFTMinting already deployed at ${existingMinting.address}`);
  }

  // Deploy BoostEngine
  const existingBoost = await getOrNull("BoostEngine");
  if (!existingBoost) {
    const boost = await deploy("BoostEngine", {
      from: deployer,
      args: [mfhToken, treasury],
      log: true,
    });
    log(` BoostEngine deployed at ${boost.address} | Gas used: ${boost.receipt.gasUsed}`);
  } else {
    log(` BoostEngine already deployed at ${existingBoost.address}`);
  }

  // Deploy RoyaltyManager
  const existingRoyalty = await getOrNull("RoyaltyManager");
  if (!existingRoyalty) {
    const royalty = await deploy("RoyaltyManager", {
      from: deployer,
      args: [mfhToken, treasury],
      log: true,
    });
    log(` RoyaltyManager deployed at ${royalty.address} | Gas used: ${royalty.receipt.gasUsed}`);
  } else {
    log(` RoyaltyManager already deployed at ${existingRoyalty.address}`);
  }

  log(" NFT-related Modules deployment complete.");
};

module.exports.tags = ["NFTModules"];
