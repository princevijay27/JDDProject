import { ethers, upgrades } from "hardhat";

async function main() {
  console.log("Deploying PegStability contract...");
  const [deployer] = await ethers.getSigners();
  const _dmToken = "0xD99fAF8A6D74644C6B5125cC0eaDFcb7a3Aa63b0";
  const _treasury = deployer.address;
  const _maxSwapFees = 1000; //10%

  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy the PegStability contract
  const PegStability = await ethers.getContractFactory("PegStabilityModule");
  const pegStability = await upgrades.deployProxy(
    PegStability,
    [_dmToken, _treasury, _maxSwapFees],
    {
      initializer: "initialize",
      kind: "uups",
    },
  );

  // For upgradeable contracts, we wait for the deployment transaction
  await pegStability.waitForDeployment(); // Changed from deployed()

  // Get the deployed address
  const PegStabilityAddress = await pegStability.getAddress(); // Changed from .address
  console.log("PegStability proxy deployed to:", PegStabilityAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error deploying PegStability contract:", error);
    process.exit(1);
  });
