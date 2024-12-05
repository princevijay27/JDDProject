import { ethers, upgrades } from "hardhat";

async function main() {
  console.log("Deploying DMSRC contract...");
  const [deployer] = await ethers.getSigners();
  const _dmToken = "0xD99fAF8A6D74644C6B5125cC0eaDFcb7a3Aa63b0";
  const initialSavingsRate = "0x2386f26fc10000"; //1%
  const _governanceContract = deployer.address; //10%

  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy the DMSRC contract
  const DMSRC = await ethers.getContractFactory("DMSavingsRate");
  const dMSRC = await upgrades.deployProxy(
    DMSRC,
    [_dmToken, initialSavingsRate, _governanceContract],
    {
      initializer: "initialize",
      kind: "uups",
    },
  );

  // For upgradeable contracts, we wait for the deployment transaction
  await dMSRC.waitForDeployment(); // Changed from deployed()

  // Get the deployed address
  const DMSRCAddress = await dMSRC.getAddress(); // Changed from .address
  console.log("DMSRC proxy deployed to:", DMSRCAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error deploying DMSRC contract:", error);
    process.exit(1);
  });
