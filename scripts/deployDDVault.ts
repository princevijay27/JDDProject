import { ethers, upgrades } from "hardhat";

async function main() {
  console.log("Deploying DDVault contract...");
  const [deployer] = await ethers.getSigners();
  const _DMToken = "0xD99fAF8A6D74644C6B5125cC0eaDFcb7a3Aa63b0";
  const _oracleSecurityModule = "0x0000000000000000000000000000000000000000";
  const _owner = deployer.address; //10%

  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy the DDVault contract
  const DDVault = await ethers.getContractFactory("DDVault");
  const ddVault = await upgrades.deployProxy(
    DDVault,
    [_DMToken, _oracleSecurityModule, _owner],
    {
      initializer: "initialize",
      kind: "uups",
    },
  );

  // For upgradeable contracts, we wait for the deployment transaction
  await ddVault.waitForDeployment(); // Changed from deployed()

  // Get the deployed address
  const ddVaultAddress = await ddVault.getAddress(); // Changed from .address
  console.log("ddVault proxy deployed to:", ddVaultAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error deploying ddVault contract:", error);
    process.exit(1);
  });
