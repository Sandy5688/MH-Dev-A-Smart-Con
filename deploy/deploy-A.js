// deploy/deploy-A.js
const { deployments, getNamedAccounts, ethers } = require("hardhat");

async function main() {
  console.log(`\n Starting full deployment...\n`);

  const { deployer } = await getNamedAccounts();
  console.log(` Deploying as: ${deployer}`);

  await runDeploy("deploy-token");
  await runDeploy("deploy-nft");
  await runDeploy("deploy-marketplace");
  await runDeploy("deploy-rentals");
  await runDeploy("deploy-finance");
  await runDeploy("deploy-rewards");
  await runDeploy("deploy-escrow");

  console.log(`\n All modules deployed successfully\n`);
}

async function runDeploy(tag) {
  console.log(`\n🔧 Executing deploy script with tag: ${tag}`);
  try {
    await deployments.run(tag, {
      log: true,
    });
    console.log(` ${tag} deployed.\n`);
  } catch (err) {
    console.warn(` Skipped ${tag} — likely already deployed`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(" Deployment failed", err);
    process.exit(1);
  });
