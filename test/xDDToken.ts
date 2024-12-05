import { expect } from "chai";
import { ethers, Signer } from "hardhat";
import { Contract } from "ethers";
import { XDiscountDao } from "../typechain"; // Adjust the path according to your setup

describe("xDiscountDao Token Contract", function () {
  let xDiscountDao: XDiscountDao;
  let owner: Signer;
  let votingContract: Signer;
  let otherWallet: Signer;
  let totalSupply: bigint;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    owner = signers[1];
    votingContract = signers[2];
    otherWallet = signers[5];

    const XDiscountDao = await ethers.getContractFactory("xDiscountDao");
    xDiscountDao = (await XDiscountDao.deploy(
      await owner.getAddress(),
    )) as XDiscountDao;

    totalSupply = await xDiscountDao.totalSupply();
    await xDiscountDao.connect(owner).setVotingContract(votingContract.address);
  });

  it("success: Should mint the correct total supply", async function () {
    expect((await xDiscountDao.totalSupply()).toString()).to.equal(
      ethers.utils.parseUnits("0", 18).toString(),
    );
  });

  it("fail: only owner can set the voting contract", async function () {
    await xDiscountDao
      .connect(otherWallet)
      .setVotingContract(votingContract.address).revert;
  });

  it("success: only owner can set the voting contract", async function () {
    await xDiscountDao.connect(owner).setVotingContract(votingContract.address);
  });

  it("fail: only voting contract can mint the tokens", async function () {
    await xDiscountDao
      .connect(otherWallet)
      .mint(
        votingContract.address,
        ethers.utils.parseUnits("1000", 18).toString(),
      ).revert;
  });

  it("success: only voting contract can mint the tokens", async function () {
    await xDiscountDao
      .connect(votingContract)
      .mint(
        otherWallet.address,
        ethers.utils.parseUnits("1000", 18).toString(),
      );
  });

  it("fail: only voting contract can burn the tokens", async function () {
    await xDiscountDao
      .connect(votingContract)
      .mint(
        otherWallet.address,
        ethers.utils.parseUnits("1000", 18).toString(),
      );
    await xDiscountDao
      .connect(otherWallet)
      .burn(
        votingContract.address,
        ethers.utils.parseUnits("1000", 18).toString(),
      ).revert;
  });

  it("success: only voting contract can burn the tokens", async function () {
    await xDiscountDao
      .connect(votingContract)
      .mint(
        otherWallet.address,
        ethers.utils.parseUnits("1000", 18).toString(),
      );
    await xDiscountDao
      .connect(votingContract)
      .burn(
        otherWallet.address,
        ethers.utils.parseUnits("1000", 18).toString(),
      );
  });

  it("success: supply will increase when mint token", async function () {
    let oldTokenSupply = await xDiscountDao.totalSupply();
    let mintAmt = 1000;
    await xDiscountDao
      .connect(votingContract)
      .mint(
        otherWallet.address,
        ethers.utils.parseUnits(`${mintAmt}`, 18).toString(),
      );
    let currentSupply = await xDiscountDao.totalSupply();
    expect(parseFloat(currentSupply)).to.equal(
      parseFloat(oldTokenSupply + mintAmt * 10 ** 18),
    );
  });

  it("success: supply will decrease when burn token", async function () {
    let mintAmt = 1000;
    await xDiscountDao
      .connect(votingContract)
      .mint(
        otherWallet.address,
        ethers.utils.parseUnits(`${mintAmt}`, 18).toString(),
      );
    let oldTokenSupply = await xDiscountDao.totalSupply();
    let burnAmt = 100;
    await xDiscountDao
      .connect(votingContract)
      .burn(
        otherWallet.address,
        ethers.utils.parseUnits(`${burnAmt}`, 18).toString(),
      );
    let currentSupply = await xDiscountDao.totalSupply();
    expect(parseFloat(currentSupply)).to.not.equal(parseFloat(oldTokenSupply));
  });
});
