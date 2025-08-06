const { expect } = require("chai");
const { ethers } = require("hardhat");

describe(" Token Module (Passing)", function () {
  let deployer, user1;
  let token;

  before(async () => {
    [deployer, user1] = await ethers.getSigners();

    const MFHToken = await ethers.getContractFactory("MFHToken");
    token = await MFHToken.deploy(); // Full supply minted to deployer
    await token.waitForDeployment();
  });

  it("should deploy token with correct name and symbol", async () => {
    expect(await token.name()).to.equal("MetaFunHub");
    expect(await token.symbol()).to.equal("MFH");
  });

  it("should return totalSupply equal to MAX_SUPPLY", async () => {
    const supply = await token.totalSupply();
    expect(supply).to.equal(ethers.parseEther("1000000000"));
  });

  it("should allow owner to pause and unpause", async () => {
    await token.pause();
    expect(await token.paused()).to.equal(true);

    await token.unpause();
    expect(await token.paused()).to.equal(false);
  });

  it("should emit Burn event when burned", async () => {
    const burnAmount = ethers.parseEther("1000");

    // Transfer some to user1 first (from deployer who owns full supply)
    await token.transfer(user1.address, burnAmount);

    // Burn from user1's balance by owner
    await expect(token.burn(user1.address, burnAmount))
      .to.emit(token, "Burn")
      .withArgs(user1.address, burnAmount);

    const userBalance = await token.balanceOf(user1.address);
    expect(userBalance).to.equal(0);
  });
});
