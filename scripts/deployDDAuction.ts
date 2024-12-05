import { ethers, upgrades } from "hardhat";

async function main() {
  console.log("Deploying DDAuction contract...");
  const [deployer] = await ethers.getSigners();
  const _dmToken = "0xD99fAF8A6D74644C6B5125cC0eaDFcb7a3Aa63b0";
  const _ddToken = "0x13695D91d8D684d224F98E1B19916E1122eaa190";
  const _ddVaultAddress = "0x6665fA18504225bB91055352Afa4b25F78eef9C7"; //10%
  const _treasury = deployer.address; //10%

  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy the DDAuction contract
  const DDAuction = await ethers.getContractFactory("DDProtocolAuction");
  const ddAuction = await upgrades.deployProxy(
    DDAuction,
    [_dmToken, _ddToken, _ddVaultAddress, _treasury],
    {
      initializer: "initialize",
      kind: "uups",
    },
  );

  // For upgradeable contracts, we wait for the deployment transaction
  await ddAuction.waitForDeployment(); // Changed from deployed()

  // Get the deployed address
  const ddAuctionAddress = await ddAuction.getAddress(); // Changed from .address
  console.log("ddAuction proxy deployed to:", ddAuctionAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error deploying ddAuction contract:", error);
    process.exit(1);
  });
