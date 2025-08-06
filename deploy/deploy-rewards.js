module.exports = async function (hre) {
  const { deployments, getNamedAccounts, ethers } = hre;
  const { deploy, getOrNull, log } = deployments;
  const { deployer } = await getNamedAccounts();
  log(" Deploying Rewards Module...");

  const mfh = (await deployments.get("MFHToken")).address;
  const staking = (await deployments.get("StakingRewards")).address;

  // Chainlink VRF config
  const vrfCoordinator = process.env.VRF_COORDINATOR;
  const linkToken = process.env.LINK_TOKEN;
  const keyHash = process.env.KEY_HASH;

  // Use ethers.parseUnits for ethers.js v6
  const fee = ethers.parseUnits("0.1", 18);
  const jackpotAmount = ethers.parseUnits("1000", 18);
  const dailyReward = ethers.parseUnits("25", 18);

  // 1. RewardDistributor
  const rewardDistributor = await getOrNull("RewardDistributor");
  if (!rewardDistributor) {
    const deployed = await deploy("RewardDistributor", {
      from: deployer,
      args: [mfh],
      log: true,
    });
    log(` RewardDistributor: ${deployed.address}`);
  } else {
    log(` RewardDistributor already at ${rewardDistributor.address}`);
  }

  // 2. SecretJackpot
  const secretJackpot = await getOrNull("SecretJackpot");
  if (!secretJackpot) {
    const deployed = await deploy("SecretJackpot", {
      from: deployer,
      args: [
        staking,
        vrfCoordinator,
        linkToken,
        keyHash,
        fee,
        mfh,
        jackpotAmount,
      ],
      log: true,
    });
    log(` SecretJackpot: ${deployed.address}`);
  } else {
    log(` SecretJackpot already at ${secretJackpot.address}`);
  }

  // 3. CheckInReward
  const checkInReward = await getOrNull("CheckInReward");
  if (!checkInReward) {
    const deployed = await deploy("CheckInReward", {
      from: deployer,
      args: [mfh, dailyReward],
      log: true,
    });
    log(` CheckInReward: ${deployed.address}`);
  } else {
    log(` CheckInReward already at ${checkInReward.address}`);
  }

  log(" Rewards Module deployed.");
};

module.exports.tags = ["RewardsModule"];