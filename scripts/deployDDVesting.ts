import { ethers, upgrades } from "hardhat";

async function main() {
  console.log("Deploying DDVesting contract...");
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  // console.log("Account balance:", (await deployer).toString());

  // Deploy the DDVesting contract
  const DDVesting = await ethers.getContractFactory("DDVesting");
  const ddVesting = await upgrades.deployProxy(DDVesting, [deployer.address], {
    initializer: "initialize",
    kind: "uups",
  });

  // For upgradeable contracts, we wait for the deployment transaction
  await ddVesting.waitForDeployment(); // Changed from deployed()

  // Get the deployed address
  const ddVestingAddress = await ddVesting.getAddress(); // Changed from .address
  console.log("DDVesting proxy deployed to:", ddVestingAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error deploying DDVesting contract:", error);
    process.exit(1);
  });
