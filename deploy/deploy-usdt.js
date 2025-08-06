const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const admin = process.env.ADMIN_ADDRESS || deployer;
  const minter = process.env.MINTER_ADDRESS || deployer;

  log(" Deploying MFH USDT Token...");

  const usdt = await deploy("USDT", {
    from: deployer,
    args: [admin, minter],
    log: true,
  });

  log(` MFHUSDT deployed at ${usdt.address}`);
};

module.exports.tags = ["USDTToken"];
