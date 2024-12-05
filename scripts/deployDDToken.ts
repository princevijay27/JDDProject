import { ethers, upgrades } from "hardhat";

async function main() {
  console.log("Deploying DDToken contract...");
  const [deployer] = await ethers.getSigners();
  const _developmentAddress = deployer.address;
  const _community = deployer.address;
  const _businesses = deployer.address;
  const _airdropAddress = deployer.address;
  const _vestingContract = "0xa0E9B95c27FD6285E45B5Cc2958d1C3Bd0cCffA1";
  const initialOwner = deployer.address;

  console.log("Deploying contracts with the account:", deployer.address);

  // console.log("Account balance:", (await deployer).toString());

  // Deploy the DDToken contract
  const DDToken = await ethers.getContractFactory("DiscountDao");
  const ddToken = await upgrades.deployProxy(
    DDToken,
    [
      _developmentAddress,
      _community,
      _businesses,
      _airdropAddress,
      _vestingContract,
      initialOwner,
    ],
    {
      initializer: "initialize",
      kind: "uups",
    },
  );

  // For upgradeable contracts, we wait for the deployment transaction
  await ddToken.waitForDeployment(); // Changed from deployed()

  // Get the deployed address
  const ddTokenAddress = await ddToken.getAddress(); // Changed from .address
  console.log("ddToken proxy deployed to:", ddTokenAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error deploying DDtoken contract:", error);
    process.exit(1);
  });
