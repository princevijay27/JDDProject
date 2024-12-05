import { expect } from "chai";
import { ethers, Signer } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { Contract } from "ethers";
import { DDVesting, DiscountDao } from "../typechain"; // Adjust the path according to your setup

describe("DiscountDao Vesting Contract", function () {
  let discountDao: DiscountDao;
  let DDVesting: DDVesting;
  let owner: Signer;
  let communityMember1: Signer;
  let communityMember2: Signer;
  let communityMember3: Signer;
  let otherWallet: Signer;
  let developmentAddress: Signer;
  let communityAddress: Signer;
  let businessesAddress: Signer;
  let airdropAddress: Signer;
  let totalAmount: bigint;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    owner = signers[1];
    communityMember1 = signers[2];
    communityMember2 = signers[3];
    communityMember3 = signers[4];
    otherWallet = signers[5];
    developmentAddress = signers[6];
    communityAddress = signers[7];
    businessesAddress = signers[8];
    airdropAddress = signers[9];

    const ddVesting = await ethers.getContractFactory("DDVesting");
    DDVesting = (await ddVesting.deploy(await owner.getAddress())) as DDVesting;

    const DiscountDao = await ethers.getContractFactory("DiscountDao");
    discountDao = (await DiscountDao.deploy(
      await developmentAddress.getAddress(),
      await communityAddress.getAddress(),
      await businessesAddress.getAddress(),
      await airdropAddress.getAddress(),
      DDVesting.address,
    )) as DiscountDao;

    totalAmount = await DDVesting.totalAmount();
    await DDVesting.connect(owner).setDDTokenAddress(discountDao.address);
    await DDVesting.connect(owner).setCommunityMember(
      communityMember1.address,
      true,
    );
  });

  it("Should mint the correct total supply", async function () {
    expect((await discountDao.totalSupply()).toString()).to.equal(
      ethers.utils.parseUnits("1000000000", 18).toString(),
    );
  });

  it("balance of vesting contract must be 20% of total supply", async function () {
    expect(
      (await discountDao.balanceOf(DDVesting.address)).toString(),
    ).to.equal(ethers.utils.parseUnits("200000000", 18).toString());
  });

  it("Permonth Release Amount n/60", async function () {
    let PerMonthReleaseAmount = (
      await DDVesting.PerMonthReleaseAmount()
    ).toString();
    let expectedAmount = (
      ethers.utils.parseUnits("200000000", 18) / 60
    ).toString();
    expect(parseFloat(PerMonthReleaseAmount)).to.equal(
      parseFloat(expectedAmount),
    );
  });

  describe("Only owner can set community member", function () {
    it("Success: Should allow only owner to set community member", async function () {
      await DDVesting.connect(owner).setCommunityMember(
        communityMember2.address,
        true,
      );
      const isCommunityMember2 = await DDVesting.isCommunityMember(
        communityMember2.address,
      );
      expect(isCommunityMember2).to.eq(true);
    });
    it("Fail: Should fail only owner to set community member", async function () {
      await DDVesting.connect(otherWallet).setCommunityMember(
        communityMember3.address,
        true,
      ).revert;
      const isCommunityMember3 = await DDVesting.isCommunityMember(
        communityMember3.address,
      );
      expect(isCommunityMember3).to.not.eq(true);
    });
  });

  describe("Only owner can set DD token address", function () {
    it("Success: Should allow only owner to set dd token address", async function () {
      await DDVesting.connect(owner).setDDTokenAddress(discountDao.address);
      const ddAddress = await DDVesting.DDToken();
      expect(ddAddress).to.eq(discountDao.address);
    });
    it("Fail: Should allow only owner to set dd token address", async function () {
      await DDVesting.connect(otherWallet).setDDTokenAddress(
        discountDao.address,
      ).revert;
    });
  });

  describe("Claim Token Function", async function () {
    it("Fail: Not Community Member", async function () {
      let monthcount = 1;
      await DDVesting.connect(otherWallet).claimToken(monthcount).revert;
    });

    it("Fail: Can be claimed for 5 years only", async function () {
      let monthcount = 66;
      await DDVesting.connect(communityMember1).claimToken(monthcount).revert;
    });

    it("Fail: Can not Claim amount for this month time has not passed yet", async function () {
      let monthcount = 1;
      await DDVesting.connect(communityMember1).claimToken(monthcount).revert;
    });

    it("Success: Community member can claim the token", async function () {
      let monthcount = 1;
      await time.increase(time.duration.days(31));
      await DDVesting.connect(communityMember1).claimToken(monthcount);
    });

    it("Fail: Can be claim once per month", async function () {
      let monthcount = 1;
      await time.increase(time.duration.days(31));
      await DDVesting.connect(communityMember1).claimToken(monthcount);
      await DDVesting.connect(communityMember2).claimToken(monthcount).revert;
    });
  });
});
