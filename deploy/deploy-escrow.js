const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, getOrNull, log } = deployments;
  const { deployer } = await getNamedAccounts();

  log(" Deploying Escrow Module...");

  const nftAddress = (await deployments.get("NFTMinting")).address;

  // -----------------------------
  // 1. Deploy MultiSigAdmin
  // -----------------------------
  const multisig = await getOrNull("MultiSigAdmin");
  if (!multisig) {
    const signer1 = deployer;
    const signer2 = "0x21E3d8EDDdd70b83B0b261c689fD1a3F350c42F5"; // 🔁 Replace with real address
    const signer3 = "0x21E3d8EDDdd70b83B0b261c689fD1a3F350c42F5"; // 🔁 Replace with real address

    const deployed = await deploy("MultiSigAdmin", {
      from: deployer,
      args: [[signer1, signer2, signer3]],
      log: true,
    });

    log(` MultiSigAdmin deployed: ${deployed.address} | Gas: ${deployed.receipt.gasUsed.toString()}`);
  } else {
    log(` MultiSigAdmin already deployed at ${multisig.address}`);
  }

  // -----------------------------
  // 2. Deploy EscrowManager
  // -----------------------------
  const escrow = await getOrNull("EscrowManager");
  if (!escrow) {
    const deployed = await deploy("EscrowManager", {
      from: deployer,
      args: [nftAddress],
      log: true,
    });

    log(` EscrowManager deployed: ${deployed.address} | Gas: ${deployed.receipt.gasUsed.toString()}`);
  } else {
    log(` EscrowManager already deployed at ${escrow.address}`);
  }

  log(" Escrow Module deployed.");
};

module.exports.tags = ["EscrowModule"];
