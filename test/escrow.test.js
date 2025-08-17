const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("EscrowManager", () => {
  let deployer, trusted, user1, treasury;
  let mfh, nft, escrow;

  beforeEach(async () => {
    [deployer, trusted, user1, treasury] = await ethers.getSigners();

    // Deploy MFH token
    const MFHToken = await ethers.getContractFactory("MFHToken");
    mfh = await MFHToken.deploy();
    await mfh.waitForDeployment();

    // Deploy NFTMinting (uses MFH for mint price)
    const NFTMinting = await ethers.getContractFactory("NFTMinting");
    nft = await NFTMinting.deploy(mfh.target);
    await nft.waitForDeployment();

    // Fund user1 with MFH and approve NFTMinting
    const mintPrice = await nft.mintPrice();
    await mfh.transfer(user1.address, mintPrice);
    await mfh.connect(user1).approve(nft.target, mintPrice);

    // Mint NFT to user1
    await nft.connect(user1).mintNFT("ipfs://collateral");

    // Deploy EscrowManager bound to NFT contract
    const EscrowManager = await ethers.getContractFactory("EscrowManager");
    escrow = await EscrowManager.deploy(nft.target);
    await escrow.waitForDeployment();

    // Make `trusted` account a trusted module
    await escrow.connect(deployer).setTrusted(trusted.address, true);
  });

  it("should allow trusted module to lock asset", async () => {
    await nft.connect(user1).approve(escrow.target, 1);

    await expect(
      escrow.connect(trusted).lockAsset(1, user1.address)
    ).to.emit(escrow, "EscrowLocked").withArgs(user1.address, 1);

    expect(await escrow.isLocked(1)).to.equal(true);
    expect(await nft.ownerOf(1)).to.equal(escrow.target);
  });

  it("should prevent double lock", async () => {
    await nft.connect(user1).approve(escrow.target, 1);
    await escrow.connect(trusted).lockAsset(1, user1.address);

    await expect(
      escrow.connect(trusted).lockAsset(1, user1.address)
    ).to.be.revertedWith("Escrow: already locked");
  });

  it("should restrict lockAsset to trusted modules", async () => {
    await nft.connect(user1).approve(escrow.target, 1);

    await expect(
      escrow.connect(user1).lockAsset(1, user1.address)
    ).to.be.revertedWith("Escrow: caller not trusted");
  });

  it("should release asset to recipient", async () => {
    await nft.connect(user1).approve(escrow.target, 1);
    await escrow.connect(trusted).lockAsset(1, user1.address);

    await expect(
      escrow.connect(trusted).releaseAsset(1, user1.address)
    ).to.emit(escrow, "EscrowReleased").withArgs(user1.address, 1);

    expect(await nft.ownerOf(1)).to.equal(user1.address);
    expect(await escrow.isLocked(1)).to.equal(false);
  });

  it("should forfeit asset to treasury/admin", async () => {
    await nft.connect(user1).approve(escrow.target, 1);
    await escrow.connect(trusted).lockAsset(1, user1.address);

    await expect(
      escrow.connect(trusted).forfeitAsset(1, treasury.address)
    ).to.emit(escrow, "EscrowForfeited").withArgs(treasury.address, 1);

    expect(await nft.ownerOf(1)).to.equal(treasury.address);
    expect(await escrow.isLocked(1)).to.equal(false);
  });

  it("should not release or forfeit if not locked", async () => {
    await expect(
      escrow.connect(trusted).releaseAsset(1, user1.address)
    ).to.be.revertedWith("Escrow: not locked");

    await expect(
      escrow.connect(trusted).forfeitAsset(1, treasury.address)
    ).to.be.revertedWith("Escrow: not locked");
  });
});
