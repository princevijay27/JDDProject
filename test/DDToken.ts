import { expect } from "chai";
import { ethers, Signer } from "hardhat";
import { Contract } from "ethers";
import { DiscountDao } from "../typechain"; // Adjust the path according to your setup

describe("DiscountDao Token Contract", function () {
  let discountDao: DiscountDao;
  let developmentAddress: Signer;
  let communityAddress: Signer;
  let businessesAddress: Signer;
  let airdropAddress: Signer;
  let vestingContractAddress: Signer;
  let totalSupply: bigint;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    developmentAddress = signers[1];
    communityAddress = signers[2];
    businessesAddress = signers[3];
    airdropAddress = signers[4];
    vestingContractAddress = signers[5];

    const DiscountDao = await ethers.getContractFactory("DiscountDao");
    discountDao = (await DiscountDao.deploy(
      await developmentAddress.getAddress(),
      await communityAddress.getAddress(),
      await businessesAddress.getAddress(),
      await airdropAddress.getAddress(),
      await vestingContractAddress.getAddress(),
    )) as DiscountDao;

    totalSupply = await discountDao.totalSupply();
  });

  it("Should mint the correct total supply", async function () {
    expect((await discountDao.totalSupply()).toString()).to.equal(
      ethers.utils.parseUnits("1000000000", 18).toString(),
    );
  });

  const allocations = [
    { name: "development", percentage: 30, address: () => developmentAddress },
    {
      name: "businesses & partners",
      percentage: 20,
      address: () => businessesAddress,
    },
    { name: "community", percentage: 25, address: () => communityAddress },
    {
      name: "vesting contract",
      percentage: 20,
      address: () => vestingContractAddress,
    },
    { name: "airdrops", percentage: 5, address: () => airdropAddress },
  ];

  for (const { name, percentage, address } of allocations) {
    it(`Should allocate ${percentage}% of tokens to ${name}`, async function () {
      const addr = await address().getAddress();
      const allocation = await discountDao.balanceOf(addr);
      expect(allocation.toString()).to.equal(
        totalSupply.mul(percentage).div(100).toString(),
      );
    });
  }
});
