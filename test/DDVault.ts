import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe.only("DDVault Contract", function () {
  let ddVault: Contract;
  let collateralToken: Contract;
  let dmToken: Contract;
  let mockOracle: Contract;
  let mockAuction: Contract;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let governance: SignerWithAddress;

  const initialSupply = ethers.utils.parseEther("1000000");
  const collateralAmount = ethers.utils.parseEther("1000");
  const dmAmount = ethers.utils.parseEther("500");

  beforeEach(async function () {
    [owner, user1, user2, governance] = await ethers.getSigners();

    // Deploy mock tokens
    const MockToken = await ethers.getContractFactory("MockToken");
    collateralToken = await MockToken.deploy(
      "Collateral",
      "COL",
      initialSupply,
    );
    dmToken = await MockToken.deploy("DM Token", "DM", initialSupply);

    // Deploy mock oracle
    const MockOracle = await ethers.getContractFactory("MockOracle");
    mockOracle = await MockOracle.deploy();

    // Deploy mock auction contract
    const MockAuction = await ethers.getContractFactory("MockAuction");
    mockAuction = await MockAuction.deploy();

    // Deploy DDVault
    const DDVault = await ethers.getContractFactory("DDVault");
    ddVault = await DDVault.deploy(
      dmToken.address,
      governance.address,
      mockOracle.address,
      mockAuction.address,
    );

    await ddVault
      .connect(governance)
      .setAllowedCollateralTokens(collateralToken.address);

    // Set initial parameters
    await ddVault
      .connect(governance)
      .setLiquidationRatio(collateralToken.address, 150); // 150%
    await ddVault.connect(governance).setStabilityFeeRate(5); // 0.05% per year

    // Approve tokens
    await collateralToken
      .connect(user1)
      .approve(ddVault.address, ethers.constants.MaxUint256);
    await dmToken
      .connect(user1)
      .approve(ddVault.address, ethers.constants.MaxUint256);
  });

  describe("Deployment", function () {
    it("Should set the correct token addresses", async function () {
      expect(await ddVault.allowedCollateral(collateralToken.address)).to.equal(
        true,
      );
      expect(await ddVault.DMToken()).to.equal(dmToken.address);
    });

    it("Should set the correct governance address", async function () {
      expect(await ddVault.governance()).to.equal(governance.address);
    });
  });

  describe.only("Vault Operations", function () {
    let vaultId: number;

    beforeEach(async function () {
      await ddVault.connect(user1).createVault(collateralToken.address);
      vaultId = 0; // First vault ID
      await collateralToken.transfer(user1.address, collateralAmount);
      await dmToken.transfer(ddVault.address, initialSupply); // Fund the vault with DM tokens
    });

    it("Should create a new vault", async function () {
      const vault = await ddVault.vaults(vaultId);
      expect(vault.owner).to.equal(user1.address);
      expect(vault.collateralToken).to.equal(collateralToken.address);
    });

    it("Should add collateral to the vault", async function () {
      await ddVault.connect(user1).addCollateral(vaultId, collateralAmount);
      const vault = await ddVault.vaults(vaultId);
      expect(vault.collateralAmount.toString()).to.equal(
        collateralAmount.toString(),
      );
    });

    it("Should generate DM tokens", async function () {
      await ddVault.connect(user1).addCollateral(vaultId, collateralAmount);
      await mockOracle.setPrice(
        collateralToken.address,
        ethers.utils.parseEther("1"),
      ); // 1:1 ratio for simplicity
      await ddVault.connect(user1).generateDM(vaultId, dmAmount);
      const vault = await ddVault.vaults(vaultId);
      expect(vault.debtAmount.toString()).to.equal(dmAmount.toString());
    });

    it("Should repay debt", async function () {
      // Add collateral
      await ddVault.connect(user1).addCollateral(vaultId, collateralAmount);

      // Set oracle price
      await mockOracle.setPrice(
        collateralToken.address,
        ethers.utils.parseEther("1"),
      );

      // Generate DM
      await ddVault.connect(user1).generateDM(vaultId, dmAmount);

      // Get the vault state after generating DM
      let vault = await ddVault.vaults(vaultId);
      const initialDebt = vault.debtAmount;
      const initialStabilityFee = vault.stabilityFeeAccrued;

      // Repay half of the debt
      const repayAmount = dmAmount.div(2);
      await ddVault.connect(user1).repayDebt(vaultId, repayAmount);

      // Get the updated vault state
      vault = await ddVault.vaults(vaultId);

      // Calculate the expected remaining debt considering stability fee
      const totalInitialDebt = initialDebt.add(initialStabilityFee);
      let expectedRemainingDebt;
      if (repayAmount.gt(initialStabilityFee)) {
        expectedRemainingDebt = totalInitialDebt.sub(repayAmount);
      } else {
        expectedRemainingDebt = initialDebt;
      }

      // Check if the remaining debt is close to the expected value
      const tolerance = ethers.utils.parseUnits("10000", "gwei");
      const debtDifference = vault.debtAmount.sub(expectedRemainingDebt).abs();

      expect(debtDifference.lte(tolerance)).to.be.true,
        `Debt amount ${vault.debtAmount.toString()} is not close enough to expected ${expectedRemainingDebt.toString()}. 
        Difference: ${debtDifference.toString()}, Tolerance: ${tolerance.toString()}.
        Initial debt: ${initialDebt.toString()}, Initial stability fee: ${initialStabilityFee.toString()}, 
        Repay amount: ${repayAmount.toString()}`;

      // Check that stability fee has been accrued or fully paid
      if (repayAmount.gt(initialStabilityFee)) {
        expect(vault.stabilityFeeAccrued.isZero()).to.be.true,
          `Expected stability fee to be 0, but got ${vault.stabilityFeeAccrued.toString()}`;
      } else {
        const expectedRemainingFee = initialStabilityFee.sub(repayAmount);
        expect(vault.stabilityFeeAccrued.eq(expectedRemainingFee)).to.be.true,
          `Expected stability fee to be ${expectedRemainingFee.toString()}, but got ${vault.stabilityFeeAccrued.toString()}`;
      }
    });

    it("Should withdraw collateral", async function () {
      await ddVault.connect(user1).addCollateral(vaultId, collateralAmount);
      await ddVault
        .connect(user1)
        .withdrawCollateral(vaultId, collateralAmount.div(2));
      const vault = await ddVault.vaults(vaultId);
      expect(vault.collateralAmount.toString()).to.equal(
        collateralAmount.div(2).toString(),
      );
    });

    it("Should not allow generating DM with insufficient collateral", async function () {
      await ddVault.connect(user1).addCollateral(vaultId, collateralAmount);
      await mockOracle.setPrice(
        collateralToken.address,
        ethers.utils.parseEther("1"),
      );
      await expect(
        ddVault.connect(user1).generateDM(vaultId, collateralAmount.mul(2)),
      ).to.be.rejectedWith("Insufficient collateral");
    });

    it("Should accrue stability fee over time", async function () {
      await ddVault.connect(user1).addCollateral(vaultId, collateralAmount);
      await mockOracle.setPrice(ethers.utils.parseEther("1"));
      await ddVault.connect(user1).generateDM(vaultId, dmAmount);

      await time.increase(365 * 24 * 60 * 60); // Advance time by 1 year
      await ddVault.connect(user1).repayDebt(vaultId, 0); // Trigger fee update

      const vault = await ddVault.vaults(vaultId);
      expect(vault.stabilityFeeAccrued).to.be.gt(0);
    });
  });

  describe("Liquidation", function () {
    let vaultId: number;

    beforeEach(async function () {
      await ddVault.connect(user1).createVault(collateralToken.address);
      vaultId = 0;
      await collateralToken.transfer(user1.address, collateralAmount);
      await dmToken.transfer(ddVault.address, initialSupply);
      await ddVault.connect(user1).addCollateral(vaultId, collateralAmount);
      await mockOracle.setPrice(ethers.utils.parseEther("1"));
      await ddVault.connect(user1).generateDM(vaultId, dmAmount);
    });

    it("Should allow liquidation when vault becomes unsafe", async function () {
      await mockOracle.setPrice(ethers.utils.parseEther("0.5")); // Drop collateral price
      await expect(ddVault.connect(user2).liquidateVault(vaultId))
        .to.emit(ddVault, "VaultLiquidated")
        .withArgs(vaultId, 0, collateralAmount, dmAmount.mul(11).div(10)); // 10% liquidation penalty
    });

    it("Should not allow liquidation of safe vaults", async function () {
      await expect(
        ddVault.connect(user2).liquidateVault(vaultId),
      ).to.be.rejectedWith("Vault is safe");
    });

    it("Should transfer collateral to auction contract during liquidation", async function () {
      await mockOracle.setPrice(ethers.utils.parseEther("0.5")); // Drop collateral price
      await ddVault.connect(user2).liquidateVault(vaultId);
      expect(await collateralToken.balanceOf(mockAuction.address)).to.equal(
        collateralAmount,
      );
    });

    it("Should reset vault after liquidation", async function () {
      await mockOracle.setPrice(ethers.utils.parseEther("0.5")); // Drop collateral price
      await ddVault.connect(user2).liquidateVault(vaultId);
      const vault = await ddVault.vaults(vaultId);
      expect(vault.collateralAmount).to.equal(0);
      expect(vault.debtAmount).to.equal(0);
      expect(vault.stabilityFeeAccrued).to.equal(0);
    });
  });

  describe("Governance", function () {
    it("Should allow governance to set liquidation penalty", async function () {
      await ddVault.connect(governance).setLiquidationPenalty(2000); // 20%
      expect(await ddVault.liquidationPenalty()).to.equal(2000);
    });

    it("Should allow governance to set auction duration", async function () {
      const newDuration = 2 * 24 * 60 * 60; // 2 days
      await ddVault.connect(governance).setAuctionDuration(newDuration);
      expect(await ddVault.auctionDuration()).to.equal(newDuration);
    });

    it("Should allow governance to set auction contract", async function () {
      const newAuctionContract = await (
        await ethers.getContractFactory("MockAuction")
      ).deploy();
      await ddVault
        .connect(governance)
        .setAuctionContract(newAuctionContract.address);
      expect(await ddVault.auctionContract()).to.equal(
        newAuctionContract.address,
      );
    });

    it("Should not allow non-governance to set liquidation parameters", async function () {
      await expect(
        ddVault.connect(user1).setLiquidationPenalty(2000),
      ).to.be.rejectedWith("Not authorized");
      await expect(
        ddVault.connect(user1).setAuctionDuration(2 * 24 * 60 * 60),
      ).to.be.rejectedWith("Not authorized");
      await expect(
        ddVault.connect(user1).setAuctionContract(ethers.constants.AddressZero),
      ).to.be.rejectedWith("Not authorized");
    });
  });
});
