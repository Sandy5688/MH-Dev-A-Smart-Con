const { expect } = require("chai");
const { ethers } = require("hardhat");

describe(" RewardsModules", () => {
  let owner, user1, user2, token, checkIn, distributor;

  const rewardAmount = ethers.parseEther("10");

  beforeEach(async () => {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy MFH token
    const MFHToken = await ethers.getContractFactory("MFHToken");
    token = await MFHToken.deploy();
    await token.waitForDeployment();

    // Fund owner with initial tokens for distribution
    await token.transfer(owner.address, ethers.parseEther("2000")); // Increased initial amount

    // Deploy CheckInReward
    const CheckInReward = await ethers.getContractFactory("CheckInReward");
    checkIn = await CheckInReward.deploy(token.target, rewardAmount);
    await checkIn.waitForDeployment();

    // Fund checkIn contract
    await token.transfer(checkIn.target, ethers.parseEther("100"));

    // Deploy RewardDistributor
    const RewardDistributor = await ethers.getContractFactory("RewardDistributor");
    distributor = await RewardDistributor.deploy(token.target);
    await distributor.waitForDeployment();
    await distributor.waitForDeployment();

    // Fund distributor
    await token.transfer(distributor.target, ethers.parseEther("100"));
  });

  describe(" CheckInReward", () => {
    it("should allow daily check-in and distribute reward", async () => {
      await checkIn.connect(user1).checkIn();
      const balance = await token.balanceOf(user1.address);
      expect(balance).to.equal(rewardAmount);
    });

    it("should not allow multiple check-ins in 24h", async () => {
      await checkIn.connect(user1).checkIn();
      await expect(checkIn.connect(user1).checkIn()).to.be.revertedWith("Already checked in today");
    });
  });

  describe(" RewardDistributor", () => {
    beforeEach(async () => {
      // Start each test with clean balances
      await token.connect(user1).transfer(owner.address, await token.balanceOf(user1.address)).catch(() => {});
      await token.connect(user2).transfer(owner.address, await token.balanceOf(user2.address)).catch(() => {});
      
      // Fund distributor with exact amount needed for the test
      const distributorBalance = await token.balanceOf(distributor.target);
      if (distributorBalance > 0) {
        await distributor.withdrawLeftover(owner.address, distributorBalance);
      }
      await token.transfer(distributor.target, rewardAmount * 2n); // Exact amount for two rewards
    });

    it("should distribute rewards to multiple users", async () => {
      // Clear any leftover balances just to be sure
      await token.connect(user1).transfer(owner.address, await token.balanceOf(user1.address)).catch(() => {});
      await token.connect(user2).transfer(owner.address, await token.balanceOf(user2.address)).catch(() => {});
      await distributor.withdrawLeftover(owner.address, await token.balanceOf(distributor.target)).catch(() => {});

      // Fund distributor with exact amount
      const distributionAmount = rewardAmount * 2n;
      await token.transfer(distributor.target, distributionAmount);

      // Log initial state
      console.log("Initial state:");
      console.log("User1 balance:", (await token.balanceOf(user1.address)).toString());
      console.log("User2 balance:", (await token.balanceOf(user2.address)).toString());
      console.log("Distributor balance:", (await token.balanceOf(distributor.target)).toString());

      // Verify initial state
      expect(await token.balanceOf(user1.address)).to.equal(0n, "User1 should start with 0");
      expect(await token.balanceOf(user2.address)).to.equal(0n, "User2 should start with 0");
      expect(await token.balanceOf(distributor.target)).to.equal(distributionAmount, "Distributor should have exact amount");

      // Distribute rewards
      const users = [user1.address, user2.address];
      const amounts = [rewardAmount, rewardAmount];
      await distributor.distribute(users, amounts);

      // Log final state
      console.log("\nFinal state:");
      console.log("User1 balance:", (await token.balanceOf(user1.address)).toString());
      console.log("User2 balance:", (await token.balanceOf(user2.address)).toString());
      console.log("Distributor balance:", (await token.balanceOf(distributor.target)).toString());

      // Verify final state
      const user1Balance = await token.balanceOf(user1.address);
      const user2Balance = await token.balanceOf(user2.address);
      const distributorBalance = await token.balanceOf(distributor.target);

      expect(user1Balance).to.equal(rewardAmount, "User1 final balance incorrect");
      expect(user2Balance).to.equal(rewardAmount, "User2 final balance incorrect");
      expect(distributorBalance).to.equal(0n, "Distributor should have 0 balance after");
    });

    it("should not distribute if balance is insufficient", async () => {
      const users = [user1.address, user2.address];
      const large = ethers.parseEther("1000");
      const amounts = [large, large];
      await expect(distributor.distribute(users, amounts)).to.be.revertedWith("Insufficient funds");
    });

    it("should allow admin to withdraw leftovers", async () => {
      const before = await token.balanceOf(owner.address);
      const withdrawAmount = ethers.parseEther("10");

      await distributor.withdrawLeftover(owner.address, withdrawAmount);
      const after = await token.balanceOf(owner.address);

      expect(after - before).to.equal(withdrawAmount);
    });
  });
});
