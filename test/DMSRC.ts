import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { DMToken } from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("DMSRC Contract", function () {
  let dmToken: DMToken;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  beforeEach(async function () {
    const DMToken = await ethers.getContractFactory("DMSRC");
    [owner, user1, user2] = await ethers.getSigners();
    dmToken = await DMToken.deploy();
    await dmToken.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await dmToken.owner()).to.equal(owner.address);
    });

    it("Should mint initial supply to the owner", async function () {
      const initialSupply = ethers.utils.parseEther("1000000");
      expect(parseFloat(await dmToken.balanceOf(owner.address))).to.eq(
        parseFloat(initialSupply),
      );
    });
  });

  describe("Minting and Burning", function () {
    it("Should allow owner to mint tokens", async function () {
      const mintAmount = ethers.utils.parseEther("1000");
      await dmToken.mint(user1.address, mintAmount);
      expect(parseFloat(await dmToken.balanceOf(user1.address))).to.eq(
        parseFloat(mintAmount),
      );
    });

    it("Should not allow non-owner to mint tokens", async function () {
      const mintAmount = ethers.utils.parseEther("1000");
      await expect(
        dmToken.connect(user1).mint(user1.address, mintAmount),
      ).to.be.rejectedWith(dmToken, "OwnableUnauthorizedAccount");
    });

    it("Should allow users to burn their tokens", async function () {
      const mintAmount = ethers.utils.parseEther("1000");
      const burnAmount = ethers.utils.parseEther("500");
      await dmToken.mint(user1.address, mintAmount);
      await dmToken.connect(user1).burn(burnAmount);
      expect(parseFloat(await dmToken.balanceOf(user1.address))).to.eq(
        parseFloat(mintAmount.sub(burnAmount)),
      );
    });
  });

  describe("DM Savings Rate", function () {
    it("Should allow owner to set DM Savings Rate", async function () {
      const newRate = ethers.utils.parseEther("0.05"); // 5% APY
      await dmToken.setDMSavingsRate(newRate);
      expect(parseFloat(await dmToken.dmSavingsRate())).to.eq(
        parseFloat(newRate),
      );
    });

    it("Should not allow non-owner to set DM Savings Rate", async function () {
      const newRate = ethers.utils.parseEther("0.05");
      await expect(
        dmToken.connect(user1).setDMSavingsRate(newRate),
      ).to.be.rejectedWith(dmToken, "OwnableUnauthorizedAccount");
    });
  });

  describe("Savings Functionality", function () {
    beforeEach(async function () {
      // Mint some tokens to user1
      await dmToken.mint(user1.address, ethers.utils.parseEther("1000"));
      // Set DM Savings Rate to 5% APY
      await dmToken.setDMSavingsRate(ethers.utils.parseEther("0.05"));
    });

    it("Should allow users to deposit to savings", async function () {
      const depositAmount = ethers.utils.parseEther("100");
      await dmToken.connect(user1).depositToSavings(depositAmount);
      expect(parseFloat(await dmToken.savingsBalances(user1.address))).to.eq(
        parseFloat(depositAmount),
      );
    });

    it("Should allow users to withdraw from savings", async function () {
      const depositAmount = ethers.utils.parseEther("100");
      const withdrawAmount = ethers.utils.parseEther("50");
      await dmToken.connect(user1).depositToSavings(depositAmount);
      await dmToken.connect(user1).withdrawFromSavings(withdrawAmount);
      const finalBalance = await dmToken.savingsBalances(user1.address);

      // Check if the final balance is within 0.001% of the expected balance
      const expectedBalance = depositAmount.sub(withdrawAmount);
      const tolerance = expectedBalance.mul(1).div(100000); // 0.001% tolerance

      expect(parseFloat(finalBalance)).to.be.gte(parseFloat(expectedBalance));
      expect(parseFloat(finalBalance)).to.be.lte(
        parseFloat(expectedBalance.add(tolerance)),
      );
    });

    it("Should accrue interest on savings", async function () {
      const depositAmount = ethers.utils.parseEther("100");
      await dmToken.connect(user1).depositToSavings(depositAmount);

      // Advance time by 1 year
      await time.increase(365 * 24 * 60 * 60);

      // Update savings to trigger interest accrual
      await dmToken.updateSavings(user1.address);

      const expectedBalance = depositAmount.mul(105).div(100); // 5% interest
      const actualBalance = await dmToken.getSavingsBalance(user1.address);
      expect(parseFloat(actualBalance)).to.be.closeTo(
        parseFloat(expectedBalance),
        parseFloat(ethers.utils.parseEther("0.000001")),
      );
    });
  });
});
