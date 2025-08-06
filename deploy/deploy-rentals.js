const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log, getOrNull } = deployments;
  const { deployer } = await getNamedAccounts();

  log(" Deploying Rental Module...");

  const nft = (await deployments.get("NFTMinting")).address;

  // ------------------------------------
  // 1. RentalEngine
  // ------------------------------------
  const existingEngine = await getOrNull("RentalEngine");
  if (!existingEngine) {
    const engine = await deploy("RentalEngine", {
      from: deployer,
      args: [nft],
      log: true,
    });
    log(` RentalEngine deployed at ${engine.address} | Gas: ${engine.receipt.gasUsed.toString()}`);
  } else {
    log(` RentalEngine already deployed at ${existingEngine.address}`);
  }

  const rentalEngine = await deployments.get("RentalEngine");

  // ------------------------------------
  // 2. LeaseAgreement (needs engine + nft)
  // ------------------------------------
  const existingLease = await getOrNull("LeaseAgreement");
  if (!existingLease) {
    const lease = await deploy("LeaseAgreement", {
      from: deployer,
      args: [nft, rentalEngine.address],
      log: true,
    });
    log(` LeaseAgreement deployed at ${lease.address} | Gas: ${lease.receipt.gasUsed.toString()}`);
  } else {
    log(` LeaseAgreement already deployed at ${existingLease.address}`);
  }

  log(" Rentals Module deployed.");
};

module.exports.tags = ["RentalsModule"];
