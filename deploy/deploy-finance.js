const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, getOrNull, log } = deployments;
  const { deployer } = await getNamedAccounts();

  log(" Deploying Finance Module...");

  const nft = (await deployments.get("NFTMinting")).address;
  const mfh = (await deployments.get("MFHToken")).address;
  const escrow = (await getOrNull("EscrowManager"))?.address || "0x0000000000000000000000000000000000000000";

  // --------------------------------------------
  // 1. InstallmentLogic (Library, no deploy needed unless using external lib)
  // --------------------------------------------

  // --------------------------------------------
  // 2. LoanModule
  // --------------------------------------------
  const existingLoan = await getOrNull("LoanModule");
  if (!existingLoan) {
    const loan = await deploy("LoanModule", {
      from: deployer,
      args: [nft, mfh, escrow],
      log: true,
    });
    log(` LoanModule deployed at ${loan.address} | Gas used: ${loan.receipt.gasUsed.toString()}`);
  } else {
    log(` LoanModule already deployed at ${existingLoan.address}`);
  }

  log(" Finance Module deployed.");
};

module.exports.tags = ["FinanceModule"];
