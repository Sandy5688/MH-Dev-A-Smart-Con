const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log, getOrNull } = deployments;
  const { deployer } = await getNamedAccounts();

  log(" Deploying Token Module...");

  const multisig = process.env.MULTISIG_ADDRESS || deployer; // fallback

  // ---------------------------------------
  // 1. Deploy MFHToken
  // ---------------------------------------
  const existingMFH = await getOrNull("MFHToken");
  if (!existingMFH) {
    const mfh = await deploy("MFHToken", {
      from: deployer,
      log: true,
    });
    log(` MFHToken deployed at ${mfh.address} | Gas used: ${mfh.receipt.gasUsed.toString()}`);
  } else {
    log(" MFHToken already deployed at", existingMFH.address);
  }

  // ---------------------------------------
  // 2. Deploy TreasuryVault
  // ---------------------------------------
  const existingVault = await getOrNull("TreasuryVault");
  if (!existingVault) {
    const vault = await deploy("TreasuryVault", {
      from: deployer,
      args: [multisig],
      log: true,
    });
    log(` TreasuryVault deployed at ${vault.address} | Gas used: ${vault.receipt.gasUsed.toString()}`);
  } else {
    log(" TreasuryVault already deployed at", existingVault.address);
  }

  // ---------------------------------------
  // 3. Deploy StakingRewards (pass token address)
  // ---------------------------------------
  const mfhToken = await deployments.get("MFHToken");

  const existingStaking = await getOrNull("StakingRewards");
  if (!existingStaking) {
    const staking = await deploy("StakingRewards", {
      from: deployer,
      args: [mfhToken.address],
      log: true,
    });
    log(` StakingRewards deployed at ${staking.address} | Gas used: ${staking.receipt.gasUsed.toString()}`);
  } else {
    log(" StakingRewards already deployed at", existingStaking.address);
  }

  log(" Token Module ready.");
};

module.exports.tags = ["TokenModule"];
