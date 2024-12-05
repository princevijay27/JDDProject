import { ethers, upgrades } from "hardhat";

async function main() {
  const proxyAddress = "YOUR_PROXY_ADDRESS"; // Replace with your proxy address

  const DDVestingV2 = await ethers.getContractFactory("DDVesting");
  console.log("Upgrading DDVesting...");
  await upgrades.upgradeProxy(proxyAddress, DDVestingV2);
  console.log("DDVesting upgraded successfully");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error upgrading DDVesting contract:", error);
    process.exit(1);
  });
