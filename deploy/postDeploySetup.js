const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const signer = await ethers.getSigner(deployer);
  log(" Running post-deployment setup as:", deployer);

  const getAddress = async (name) => (await get(name)).address;
  const getContract = async (name) =>
    await ethers.getContractAt(name, await getAddress(name), signer);

  // Addresses
  const mfh = await getAddress("MFHToken");
  const vault = await getAddress("TreasuryVault");
  const royalty = await getAddress("RoyaltyManager");
  const escrow = await getContract("EscrowManager");

  // 1. Inject MFHToken
  await (await (await getContract("StakingRewards")).setToken(mfh)).wait();
  await (await (await getContract("RewardDistributor")).setToken(mfh)).wait();
  await (await (await getContract("BoostEngine")).setPaymentToken(mfh)).wait();
  await (await (await getContract("CheckInReward")).setToken(mfh)).wait();
  await (await (await getContract("LoanModule")).setToken(mfh)).wait();
  log(" MFHToken injected into all modules");

  // 2. Inject TreasuryVault
  await (await (await getContract("BoostEngine")).setTreasury(vault)).wait();
  await (await (await getContract("MarketplaceCore")).setTreasury(vault)).wait();
  await (await (await getContract("RentalEngine")).setTreasury(vault)).wait();
  log(" TreasuryVault injected into fee modules");

  // 3. Inject RoyaltyManager
  await (await (await getContract("MarketplaceCore")).setRoyaltyManager(royalty)).wait();
  log(" RoyaltyManager linked with MarketplaceCore");

  // 4. Whitelist trusted modules in EscrowManager
  const trustedModules = [
    await getAddress("BuyNowPayLater"),
    await getAddress("LoanModule"),
    await getAddress("RentalEngine"),
  ];

  for (const mod of trustedModules) {
    const tx = await escrow.setTrusted(mod, true);
    await tx.wait();
    log(` Whitelisted ${mod} in EscrowManager`);
  }

  log(" EscrowManager whitelisting complete");

  // 5. (Optional) RewardDistributor trigger address
  // const engagementContract = "0x..."; // ← set manually if you have it
  // await (await (await getContract("RewardDistributor")).setTrigger(engagementContract)).wait();
  // log(" Engagement trigger set");

  log(" Post-deploy setup complete.");
};

module.exports.tags = ["PostSetup"];
