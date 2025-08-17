const { expect } = require("chai");
const { ethers } = require("hardhat");

describe(" TokenModule", function () {
  let deployer, user1, user2, multisig;
  let token, treasury, staking;

  beforeEach(async () => {
    [deployer, user1, user2, multisig] = await ethers.getSigners();

    const MFHToken = await ethers.getContractFactory("MFHToken");
    token = await MFHToken.deploy(ethers.ZeroAddress); // pass dummy forwarder for testing
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

    it("should burn self and via allowance correctly", async () => {
      // Self-burn
      await token.connect(user1).burn(user1.address, ethers.parseEther("100"));
      expect(await token.balanceOf(user1.address)).to.equal(ethers.parseEther("900"));

      // Burn via allowance
      await token.connect(user1).approve(user2.address, ethers.parseEther("50"));
      await token.connect(user2).burn(user1.address, ethers.parseEther("50"));
      expect(await token.balanceOf(user1.address)).to.equal(ethers.parseEther("850"));

      // Burn arbitrary (should revert)
      await expect(
        token.connect(user2).burn(user2.address, ethers.parseEther("10"))
      ).to.be.revertedWith("MFH: not allowed to burn");
    });

    it("should pause and unpause transfers", async () => {
      await token.pause();
      await expect(
        token.connect(user1).transfer(user2.address, ethers.parseEther("1"))
      ).to.be.revertedWith("Pausable: paused");

      await token.unpause();

      await expect(
        token.connect(user1).transfer(user2.address, ethers.parseEther("1"))
      ).to.emit(token, "Transfer");
    });

    it("should revert mint exceeding MAX_SUPPLY", async () => {
      const maxSupply = await token.MAX_SUPPLY();
      await expect(token.mint(user1.address, maxSupply)).to.be.revertedWith(
        "MFH: max supply exceeded"
      );
    });

    it("should support meta-transactions (_msgSender())", async () => {
      // Direct call simulates meta-tx: _msgSender() == msg.sender
      await token.connect(user1).burn(user1.address, ethers.parseEther("1"));
      const bal = await token.balanceOf(user1.address);
      expect(bal).to.equal(ethers.parseEther("999")); // 1000 - 1
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

      await expect(
        treasury.connect(user2).withdraw(token.target, user2.address, ethers.parseEther("1000"))
      ).to.be.revertedWith("Vault: not authorized");

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
      await token.connect(user2).approve(staking.target, ethers.parseEther("50"));
      await staking.connect(user1).stake(ethers.parseEther("100"));
    });

    it("should allow staking and track balance", async () => {
      const stakeInfo = await staking.stakes(user1.address);
      expect(stakeInfo.amount).to.equal(ethers.parseEther("100"));
    });

    it("getEligibleAddresses returns correct stakers", async () => {
      let eligible = await staking.getEligibleAddresses();
      expect(eligible).to.include(user1.address);
      expect(eligible).to.not.include(user2.address);

      await staking.connect(user2).stake(ethers.parseEther("50"));
      eligible = await staking.getEligibleAddresses();
      expect(eligible).to.include(user2.address);
    });

    it("unstaking removes user from eligible list", async () => {
      await staking.connect(user1).unstake();
      const eligible = await staking.getEligibleAddresses();
      expect(eligible).to.not.include(user1.address);
    });

    it("pendingReward calculation respects rounding", async () => {
      const rewardRate = ethers.parseEther("0.001");
      await staking.setRewardRate(rewardRate);

      const stakedAmount = ethers.parseEther("100");
      await staking.connect(user1).unstake();
      await token.connect(user1).approve(staking.target, stakedAmount);
      await staking.connect(user1).stake(stakedAmount);

      const stakeInfo = await staking.stakes(user1.address);
      expect(stakeInfo.amount).to.equal(stakedAmount);

      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine");

      const pending = await staking.pendingReward(user1.address);
      const expected = (stakedAmount * rewardRate * BigInt(3600)) / ethers.parseEther("1");
      expect(pending).to.equal(expected);
    });

    it("staking and unstaking updates totalStaked correctly", async () => {
      let info = await staking.stakes(user1.address);
      expect(info.amount).to.equal(ethers.parseEther("100"));
      let total = await staking.totalStaked();
      expect(total).to.equal(ethers.parseEther("100"));

      await staking.connect(user1).unstake();
      total = await staking.totalStaked();
      expect(total).to.equal(0);
    });
  });
});
