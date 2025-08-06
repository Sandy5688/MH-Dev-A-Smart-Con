const { expect } = require("chai");
const { ethers } = require("hardhat");

describe(" Rewards Modules", () => {
  let owner, user1, user2, token, checkIn, distributor;

  const rewardAmount = ethers.parseEther("10");

  beforeEach(async () => {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy MFH token
    const MFHToken = await ethers.getContractFactory("MFHToken");
    token = await MFHToken.deploy();
    await token.waitForDeployment();

    // Fund owner with tokens
    await token.transfer(owner.address, ethers.parseEther("1000"));

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
    it("should distribute rewards to multiple users", async () => {
      const users = [user1.address, user2.address];
      const amounts = [rewardAmount, rewardAmount];
      await distributor.distribute(users, amounts);

      expect(await token.balanceOf(user1.address)).to.equal(rewardAmount);
      expect(await token.balanceOf(user2.address)).to.equal(rewardAmount);
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
