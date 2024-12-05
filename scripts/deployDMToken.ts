import { ethers, upgrades } from "hardhat";

async function main() {
  console.log("Deploying DMToken contract...");
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  // console.log("Account balance:", (await deployer).toString());

  // Deploy the DMToken contract
  const DMToken = await ethers.getContractFactory("DMStablecoin");
  const dmToken = await upgrades.deployProxy(DMToken, [], {
    initializer: "initialize",
    kind: "uups",
  });

  // For upgradeable contracts, we wait for the deployment transaction
  await dmToken.waitForDeployment(); // Changed from deployed()

  // Get the deployed address
  const dmTokenAddress = await dmToken.getAddress(); // Changed from .address
  console.log("dmToken proxy deployed to:", dmTokenAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error deploying DMtoken contract:", error);
    process.exit(1);
  });
