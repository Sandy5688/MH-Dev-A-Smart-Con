const { expect } = require("chai");
const { ethers } = require("hardhat");

describe(" TokenModule", function () {
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
    it("should deposit tokens to treasury and emit event", async () => {
      await token.connect(user1).approve(treasury.target, ethers.parseEther("1000"));
      await expect(treasury.connect(user1).deposit(token.target, ethers.parseEther("1000")))
        .to.emit(treasury, "DepositReceived")
        .withArgs(token.target, user1.address, ethers.parseEther("1000"));

      const balance = await token.balanceOf(treasury.target);
      expect(balance).to.equal(ethers.parseEther("1000"));
    });

    it("should allow only owner or multisig to withdraw", async () => {
      await token.connect(user1).approve(treasury.target, ethers.parseEther("1000"));
      await treasury.connect(user1).deposit(token.target, ethers.parseEther("1000"));

      // Non-admin withdraw fails
      await expect(
        treasury.connect(user2).withdraw(token.target, user2.address, ethers.parseEther("1000"))
      ).to.be.revertedWith("Vault: not authorized");

      // Admin/multisig withdraw succeeds
      await expect(
        treasury.connect(multisig).withdraw(token.target, user2.address, ethers.parseEther("500"))
      ).to.emit(treasury, "WithdrawalExecuted")
        .withArgs(token.target, user2.address, ethers.parseEther("500"));

      const balance = await token.balanceOf(treasury.target);
      expect(balance).to.equal(ethers.parseEther("500"));
    });

    it("should revert if withdrawing to zero address", async () => {
      await token.connect(user1).approve(treasury.target, ethers.parseEther("100"));
      await treasury.connect(user1).deposit(token.target, ethers.parseEther("100"));

      await expect(
        treasury.connect(multisig).withdraw(token.target, ethers.ZeroAddress, ethers.parseEther("50"))
      ).to.be.revertedWith("Vault: invalid recipient");
    });

    it("should allow recovery of stuck ERC20 tokens by admin", async () => {
      // Simulate ERC20 accidentally sent to vault
      await token.transfer(treasury.target, ethers.parseEther("10"));
      await expect(treasury.connect(multisig).recoverERC20(token.target, user1.address, ethers.parseEther("10")))
        .to.emit(treasury, "WithdrawalExecuted")
        .withArgs(token.target, user1.address, ethers.parseEther("10"));

      const balance = await token.balanceOf(user1.address);
      expect(balance).to.equal(ethers.parseEther("1010"));
    });

    it("should allow recovery of ETH by admin", async () => {
      await deployer.sendTransaction({ to: treasury.target, value: ethers.parseEther("1") });

      const before = await ethers.provider.getBalance(user1.address);
      const tx = await treasury.connect(multisig).recoverETH(user1.address, ethers.parseEther("1"));
      const receipt = await tx.wait();
      const after = await ethers.provider.getBalance(user1.address);

      expect(after - before).to.equal(ethers.parseEther("1"));
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
