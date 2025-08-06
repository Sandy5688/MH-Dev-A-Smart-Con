
require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");
require("hardhat-deploy");

module.exports = {
  solidity: "0.8.28",
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: [process.env.PRIVATE_KEY],
    },
    hardhat: {
      chainId: 31337,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || "",
  },
};
