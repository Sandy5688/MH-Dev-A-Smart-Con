const { expect } = require("chai");
const { ethers } = require("hardhat");

describe(" Token Module", function () {
  let deployer, user1, user2, multisig;
  let token, treasury, staking;

  beforeEach(async () => {
    [deployer, user1, user2, multisig] = await ethers.getSigners();

    const MFHToken = await ethers.getContractFactory("MFHToken");
    token = await MFHToken.deploy();
    await token.waitForDeployment();

    const TreasuryVault = await ethers.getContractFactory("TreasuryVault");
    treasury = await TreasuryVault.deploy(multisig.address);
    await treasury.waitForDeployment();

    const StakingRewards = await ethers.getContractFactory("StakingRewards");
    staking = await StakingRewards.deploy(token.target);
    await staking.waitForDeployment();

    // Transfer initial tokens to users
    await token.transfer(user1.address, ethers.parseEther("1000"));
    await token.transfer(user2.address, ethers.parseEther("500"));
  });

  describe(" MFHToken.sol", function () {
    it("should have correct initial balance for user1", async () => {
      const balance = await token.balanceOf(user1.address);
      expect(balance).to.equal(ethers.parseEther("1000"));
    });

    it("should burn tokens correctly", async () => {
      await token.connect(user1).approve(deployer.address, ethers.parseEther("100"));
      await token.burn(user1.address, ethers.parseEther("100"));
      const newBalance = await token.balanceOf(user1.address);
      expect(newBalance).to.equal(ethers.parseEther("900"));
    });

    it("should pause and unpause transfers", async () => {
      await token.pause();
      await expect(
        token.connect(user1).transfer(user2.address, ethers.parseEther("0.0001"))
      ).to.be.revertedWith("Pausable: paused");

      await token.unpause();

      await expect(
        token.connect(user1).transfer(user2.address, ethers.parseEther("0.0001"))
      ).to.emit(token, "Transfer");
    });
  });

  describe(" TreasuryVault.sol", function () {
    it("should deposit tokens to treasury", async () => {
      await token.connect(user1).approve(treasury.target, ethers.parseEther("1000"));
      await treasury.connect(user1).deposit(token.target, ethers.parseEther("1000"));
      const balance = await token.balanceOf(treasury.target);
      expect(balance).to.equal(ethers.parseEther("1000"));
    });

    it("should allow only owner or multisig to withdraw", async () => {
      await token.connect(user1).approve(treasury.target, ethers.parseEther("1000"));
      await treasury.connect(user1).deposit(token.target, ethers.parseEther("1000"));

      await expect(
        treasury.connect(user2).withdraw(token.target, user2.address, ethers.parseEther("1000"))
      ).to.be.revertedWith("Vault: not authorized");

      await expect(
        treasury.connect(multisig).withdraw(token.target, user2.address, ethers.parseEther("500"))
      ).to.emit(token, "Transfer");
    });
  });

  describe(" StakingRewards.sol", function () {
    beforeEach(async () => {
      await token.transfer(staking.target, ethers.parseEther("1000"));
      await token.connect(user1).approve(staking.target, ethers.parseEther("100"));
      await staking.connect(user1).stake(ethers.parseEther("100"));
    });

    it("should allow staking and track balance", async () => {
      const stakeInfo = await staking.stakes(user1.address);
      expect(stakeInfo.amount).to.equal(ethers.parseEther("100"));
    });
  });
});
