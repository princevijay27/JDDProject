import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer, ContractFactory } from "ethers";

describe("PegStabilityModule", function () {
  let pegStabilityModule: Contract;
  let dmToken: Contract;
  let mockUSDC: Contract;
  let owner: Signer;
  let MockERC20: ContractFactory;
  let treasury: Signer;
  let user1: Signer;
  let user2: Signer;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    owner = signers[0];
    treasury = signers[1];
    user1 = signers[2];
    user2 = signers[3];
    const DMStablecoin = await ethers.getContractFactory("DMStablecoin");
    dmToken = await DMStablecoin.deploy();

    MockERC20 = await ethers.getContractFactory("MockERC20");
    mockUSDC = await MockERC20.deploy("Mock USDC", "USDC");

    const PegStabilityModule =
      await ethers.getContractFactory("PegStabilityModule");
    pegStabilityModule = await PegStabilityModule.deploy(
      dmToken.address,
      await treasury.getAddress(),
      500,
    );

    await dmToken.setCommunityMember(pegStabilityModule.address, true);
    await pegStabilityModule.addAcceptedStablecoin(mockUSDC.address);

    // Mint some USDC to users
    await mockUSDC.mint(
      await user1.getAddress(),
      ethers.utils.parseUnits("1000", 6),
    );
    await mockUSDC.mint(
      await user2.getAddress(),
      ethers.utils.parseUnits("1000", 6),
    );
  });

  describe("Initialization", function () {
    it("Should set the correct DM token and treasury addresses", async function () {
      expect(await pegStabilityModule.dmToken()).to.equal(dmToken.address);
      expect(await pegStabilityModule.treasury()).to.equal(
        await treasury.getAddress(),
      );
    });

    it("Should fail if initialized with zero addresses", async function () {
      const PegStabilityModule =
        await ethers.getContractFactory("PegStabilityModule");
      await expect(
        PegStabilityModule.deploy(
          ethers.constants.AddressZero,
          await treasury.getAddress(),
        ),
      ).to.be.rejectedWith("Invalid DM token address");
    });
  });

  describe("Stablecoin Management", function () {
    it("Should add and remove accepted stablecoins", async function () {
      const newStablecoin = await MockERC20.deploy("New Stable", "NS");
      await pegStabilityModule.addAcceptedStablecoin(newStablecoin.address);
      expect(
        await pegStabilityModule.acceptedStablecoins(newStablecoin.address),
      ).to.be.true;

      await pegStabilityModule.removeAcceptedStablecoin(newStablecoin.address);
      expect(
        await pegStabilityModule.acceptedStablecoins(newStablecoin.address),
      ).to.be.false;
    });

    it("Should fail to add zero address as stablecoin", async function () {
      await expect(
        pegStabilityModule.addAcceptedStablecoin(ethers.constants.AddressZero),
      ).to.be.rejectedWith("Invalid stablecoin address");
    });

    it("Should only allow owner to add/remove stablecoins", async function () {
      const newStablecoin = await MockERC20.deploy("New Stable", "NS");
      await expect(
        pegStabilityModule
          .connect(user1)
          .addAcceptedStablecoin(newStablecoin.address),
      ).to.be.rejected;
      await expect(
        pegStabilityModule
          .connect(user1)
          .removeAcceptedStablecoin(mockUSDC.address),
      ).to.be.rejected;
    });
  });

  describe("Swap Fee Management", function () {
    it("Should update swap fee", async function () {
      await pegStabilityModule.setSwapFee(20);
      expect((await pegStabilityModule.swapFee()).toString()).to.equal("20");
    });

    it("Should fail to set swap fee above maximum", async function () {
      await expect(pegStabilityModule.setSwapFee(501)).to.be.rejectedWith(
        "Fee too high",
      );
    });

    it("Should only allow owner to update swap fee", async function () {
      await expect(pegStabilityModule.connect(user1).setSwapFee(20)).to.be
        .rejected;
    });
  });

  describe("Treasury Management", function () {
    it("Should update treasury address", async function () {
      const newTreasury = await user2.getAddress();
      await pegStabilityModule.setTreasury(newTreasury);
      expect(await pegStabilityModule.treasury()).to.equal(newTreasury);
    });

    it("Should fail to set zero address as treasury", async function () {
      await expect(
        pegStabilityModule.setTreasury(ethers.constants.AddressZero),
      ).to.be.rejectedWith("Invalid treasury address");
    });

    it("Should only allow owner to update treasury", async function () {
      await expect(
        pegStabilityModule.connect(user1).setTreasury(await user2.getAddress()),
      ).to.be.rejected;
    });
  });

  describe("Deposit Stablecoin", function () {
    it("Should deposit stablecoin and mint DM tokens", async function () {
      const depositAmount = ethers.utils.parseUnits("100", 6);
      await mockUSDC
        .connect(user1)
        .approve(pegStabilityModule.address, depositAmount);
      await pegStabilityModule
        .connect(user1)
        .depositStablecoin(mockUSDC.address, depositAmount);

      expect(
        (await dmToken.balanceOf(await user1.getAddress())).toString(),
      ).to.equal(depositAmount.toString());
      expect(
        (await mockUSDC.balanceOf(pegStabilityModule.address)).toString(),
      ).to.equal(depositAmount.toString());
    });

    it("Should fail to deposit non-accepted stablecoin", async function () {
      const newStablecoin = await MockERC20.deploy("New Stable", "NS");
      const depositAmount = ethers.utils.parseUnits("100", 18);
      await newStablecoin.mint(await user1.getAddress(), depositAmount);
      await newStablecoin
        .connect(user1)
        .approve(pegStabilityModule.address, depositAmount);

      await expect(
        pegStabilityModule
          .connect(user1)
          .depositStablecoin(newStablecoin.address, depositAmount),
      ).to.be.rejectedWith("Stablecoin not accepted");
    });

    it("Should fail to deposit zero amount", async function () {
      await expect(
        pegStabilityModule
          .connect(user1)
          .depositStablecoin(mockUSDC.address, 0),
      ).to.be.rejectedWith("Amount must be greater than 0");
    });
  });

  describe("Withdraw Stablecoin", function () {
    beforeEach(async function () {
      const depositAmount = ethers.utils.parseUnits("100", 6);
      await mockUSDC
        .connect(user1)
        .approve(pegStabilityModule.address, depositAmount);
      await pegStabilityModule
        .connect(user1)
        .depositStablecoin(mockUSDC.address, depositAmount);
    });

    it("Should withdraw stablecoin and burn DM tokens", async function () {
      const withdrawAmount = ethers.utils.parseUnits("50", 6);
      await dmToken
        .connect(user1)
        .approve(pegStabilityModule.address, withdrawAmount);
      await pegStabilityModule
        .connect(user1)
        .withdrawStablecoin(mockUSDC.address, withdrawAmount);

      const fee = withdrawAmount.mul(10).div(10000);
      const amountAfterFee = withdrawAmount.sub(fee);

      expect(
        (await dmToken.balanceOf(await user1.getAddress())).toString(),
      ).to.equal(ethers.utils.parseUnits("50", 6).toString());
      expect(
        (await mockUSDC.balanceOf(await user1.getAddress())).toString(),
      ).to.equal(
        ethers.utils.parseUnits("900", 6).add(amountAfterFee).toString(),
      );
      console.log(
        "balance",
        await mockUSDC.balanceOf(await treasury.getAddress()),
      );
      expect(
        (await mockUSDC.balanceOf(await treasury.getAddress())).toString(),
      ).to.equal(fee.toString());
    });

    it("Should fail to withdraw non-accepted stablecoin", async function () {
      const newStablecoin = await MockERC20.deploy("New Stable", "NS");
      const withdrawAmount = ethers.utils.parseUnits("50", 18);
      await dmToken
        .connect(user1)
        .approve(pegStabilityModule.address, withdrawAmount);

      await expect(
        pegStabilityModule
          .connect(user1)
          .withdrawStablecoin(newStablecoin.address, withdrawAmount),
      ).to.be.rejectedWith("Stablecoin not accepted");
    });

    it("Should fail to withdraw zero amount", async function () {
      await expect(
        pegStabilityModule
          .connect(user1)
          .withdrawStablecoin(mockUSDC.address, 0),
      ).to.be.rejectedWith("Amount must be greater than 0");
    });

    it("Should fail to withdraw more than balance", async function () {
      const withdrawAmount = ethers.utils.parseUnits("150", 6);
      await dmToken
        .connect(user1)
        .approve(pegStabilityModule.address, withdrawAmount);

      await expect(
        pegStabilityModule
          .connect(user1)
          .withdrawStablecoin(mockUSDC.address, withdrawAmount),
      ).to.be.rejected;
    });
  });

  describe("Rescue Tokens", function () {
    it("Should rescue accidentally sent tokens", async function () {
      const accidentalAmount = ethers.utils.parseUnits("10", 6);
      await mockUSDC
        .connect(user2)
        .transfer(pegStabilityModule.address, accidentalAmount);

      const initialBalance = await mockUSDC.balanceOf(await owner.getAddress());
      await pegStabilityModule.rescueTokens(
        mockUSDC.address,
        await owner.getAddress(),
        accidentalAmount,
      );
      const finalBalance = await mockUSDC.balanceOf(await owner.getAddress());

      expect(finalBalance.sub(initialBalance)).to.equal(accidentalAmount);
    });

    it("Should only allow owner to rescue tokens", async function () {
      await expect(
        pegStabilityModule
          .connect(user1)
          .rescueTokens(mockUSDC.address, await user1.getAddress(), 100),
      ).to.be.rejectedWith("Ownable: caller is not the owner");
    });

    it("Should fail to rescue tokens to zero address", async function () {
      await expect(
        pegStabilityModule.rescueTokens(
          mockUSDC.address,
          ethers.constants.AddressZero,
          100,
        ),
      ).to.be.rejectedWith("Invalid recipient");
    });
  });

  describe("Integration Tests", function () {
    it("Should handle multiple deposits and withdrawals correctly", async function () {
      const depositAmount = ethers.utils.parseUnits("100", 6);
      await mockUSDC
        .connect(user1)
        .approve(pegStabilityModule.address, depositAmount.mul(2));
      await mockUSDC
        .connect(user2)
        .approve(pegStabilityModule.address, depositAmount);

      // User1 deposits 100 USDC
      await pegStabilityModule
        .connect(user1)
        .depositStablecoin(mockUSDC.address, depositAmount);
      // User2 deposits 100 USDC
      await pegStabilityModule
        .connect(user2)
        .depositStablecoin(mockUSDC.address, depositAmount);
      // User1 deposits another 100 USDC
      await pegStabilityModule
        .connect(user1)
        .depositStablecoin(mockUSDC.address, depositAmount);

      expect(await dmToken.balanceOf(await user1.getAddress())).to.equal(
        depositAmount.mul(2),
      );
      expect(await dmToken.balanceOf(await user2.getAddress())).to.equal(
        depositAmount,
      );

      // User1 withdraws 150 USDC worth of DM
      const withdrawAmount = ethers.utils.parseUnits("150", 6);
      await dmToken
        .connect(user1)
        .approve(pegStabilityModule.address, withdrawAmount);
      await pegStabilityModule
        .connect(user1)
        .withdrawStablecoin(mockUSDC.address, withdrawAmount);

      const fee = withdrawAmount.mul(10).div(10000);
      const amountAfterFee = withdrawAmount.sub(fee);

      expect(await dmToken.balanceOf(await user1.getAddress())).to.equal(
        depositAmount.mul(2).sub(withdrawAmount),
      );
      expect(await mockUSDC.balanceOf(await user1.getAddress())).to.equal(
        ethers.utils.parseUnits("850", 6).add(amountAfterFee),
      );
      expect(await mockUSDC.balanceOf(await treasury.getAddress())).to.equal(
        fee,
      );
    });

    it("Should handle deposits and withdrawals with different stablecoins", async function () {
      const MockDAI = await ethers.getContractFactory("MockERC20");
      const mockDAI = (await MockDAI.deploy("Mock DAI", "DAI")) as MockERC20;
      await pegStabilityModule.addAcceptedStablecoin(mockDAI.address);

      await mockDAI.mint(
        await user1.getAddress(),
        ethers.utils.parseEther("1000"),
      );
      await mockDAI
        .connect(user1)
        .approve(pegStabilityModule.address, ethers.utils.parseEther("1000"));

      // Deposit 100 USDC and 100 DAI
      const depositAmount = ethers.utils.parseUnits("100", 6);
      await mockUSDC
        .connect(user1)
        .approve(pegStabilityModule.address, depositAmount);
      await pegStabilityModule
        .connect(user1)
        .depositStablecoin(mockUSDC.address, depositAmount);
      await pegStabilityModule
        .connect(user1)
        .depositStablecoin(mockDAI.address, ethers.utils.parseEther("100"));

      expect(await dmToken.balanceOf(await user1.getAddress())).to.equal(
        ethers.utils.parseEther("200"),
      );

      // Withdraw 50 USDC worth of DM
      const withdrawAmount = ethers.utils.parseUnits("50", 6);
      await dmToken
        .connect(user1)
        .approve(pegStabilityModule.address, withdrawAmount);
      await pegStabilityModule
        .connect(user1)
        .withdrawStablecoin(mockUSDC.address, withdrawAmount);

      const fee = withdrawAmount.mul(10).div(10000);
      const amountAfterFee = withdrawAmount.sub(fee);

      expect(await dmToken.balanceOf(await user1.getAddress())).to.equal(
        ethers.utils.parseEther("150"),
      );
      expect(await mockUSDC.balanceOf(await user1.getAddress())).to.equal(
        ethers.utils.parseUnits("950", 6).add(amountAfterFee),
      );
      expect(await mockUSDC.balanceOf(await treasury.getAddress())).to.equal(
        fee,
      );
    });
  });

  describe("Edge Cases", function () {
    it("Should handle minimum deposit amount correctly", async function () {
      const minDepositAmount = 1; // 1 wei
      await mockUSDC
        .connect(user1)
        .approve(pegStabilityModule.address, minDepositAmount);
      await pegStabilityModule
        .connect(user1)
        .depositStablecoin(mockUSDC.address, minDepositAmount);

      expect(await dmToken.balanceOf(await user1.getAddress())).to.equal(
        minDepositAmount,
      );
    });

    it("Should handle minimum withdrawal amount correctly", async function () {
      const depositAmount = ethers.utils.parseUnits("100", 6);
      await mockUSDC
        .connect(user1)
        .approve(pegStabilityModule.address, depositAmount);
      await pegStabilityModule
        .connect(user1)
        .depositStablecoin(mockUSDC.address, depositAmount);

      const minWithdrawAmount = 1; // 1 wei
      await dmToken
        .connect(user1)
        .approve(pegStabilityModule.address, minWithdrawAmount);
      await pegStabilityModule
        .connect(user1)
        .withdrawStablecoin(mockUSDC.address, minWithdrawAmount);

      expect(await dmToken.balanceOf(await user1.getAddress())).to.equal(
        depositAmount.sub(1),
      );
    });

    it("Should fail when trying to withdraw more than available balance", async function () {
      const depositAmount = ethers.utils.parseUnits("100", 6);
      await mockUSDC
        .connect(user1)
        .approve(pegStabilityModule.address, depositAmount);
      await pegStabilityModule
        .connect(user1)
        .depositStablecoin(mockUSDC.address, depositAmount);

      const excessAmount = depositAmount.add(1);
      await dmToken
        .connect(user1)
        .approve(pegStabilityModule.address, excessAmount);
      await expect(
        pegStabilityModule
          .connect(user1)
          .withdrawStablecoin(mockUSDC.address, excessAmount),
      ).to.be.rejectedWith("ERC20: burn amount exceeds balance");
    });

    it("Should handle maximum swap fee correctly", async function () {
      await pegStabilityModule.setSwapFee(500); // 5%

      const depositAmount = ethers.utils.parseUnits("100", 6);
      await mockUSDC
        .connect(user1)
        .approve(pegStabilityModule.address, depositAmount);
      await pegStabilityModule
        .connect(user1)
        .depositStablecoin(mockUSDC.address, depositAmount);

      await dmToken
        .connect(user1)
        .approve(pegStabilityModule.address, depositAmount);
      await pegStabilityModule
        .connect(user1)
        .withdrawStablecoin(mockUSDC.address, depositAmount);

      const fee = depositAmount.mul(500).div(10000); // 5% fee
      const amountAfterFee = depositAmount.sub(fee);

      expect(await mockUSDC.balanceOf(await user1.getAddress())).to.equal(
        ethers.utils.parseUnits("1000", 6).sub(fee),
      );
      expect(await mockUSDC.balanceOf(await treasury.getAddress())).to.equal(
        fee,
      );
    });
  });

  describe("Stress Tests", function () {
    it("Should handle a large number of deposits and withdrawals", async function () {
      const iterations = 100;
      const depositAmount = ethers.utils.parseUnits("1", 6);
      await mockUSDC
        .connect(user1)
        .approve(pegStabilityModule.address, depositAmount.mul(iterations * 2));

      for (let i = 0; i < iterations; i++) {
        await pegStabilityModule
          .connect(user1)
          .depositStablecoin(mockUSDC.address, depositAmount);
        await dmToken
          .connect(user1)
          .approve(pegStabilityModule.address, depositAmount);
        await pegStabilityModule
          .connect(user1)
          .withdrawStablecoin(mockUSDC.address, depositAmount);
      }

      const expectedBalance = ethers.utils
        .parseUnits("1000", 6)
        .sub(depositAmount.mul(iterations).mul(10).div(10000));
      expect(await mockUSDC.balanceOf(await user1.getAddress())).to.be.closeTo(
        expectedBalance,
        100,
      );
    });

    it("Should handle multiple users depositing and withdrawing simultaneously", async function () {
      const users = await ethers.getSigners();
      const depositAmount = ethers.utils.parseUnits("10", 6);

      // Mint USDC to all users
      for (let i = 0; i < 10; i++) {
        await mockUSDC.mint(users[i].address, depositAmount.mul(10));
        await mockUSDC
          .connect(users[i])
          .approve(pegStabilityModule.address, depositAmount.mul(10));
      }

      // All users deposit simultaneously
      await Promise.all(
        users
          .slice(0, 10)
          .map((user) =>
            pegStabilityModule
              .connect(user)
              .depositStablecoin(mockUSDC.address, depositAmount),
          ),
      );

      // All users withdraw simultaneously
      await Promise.all(
        users.slice(0, 10).map((user) => {
          return dmToken
            .connect(user)
            .approve(pegStabilityModule.address, depositAmount)
            .then(() =>
              pegStabilityModule
                .connect(user)
                .withdrawStablecoin(mockUSDC.address, depositAmount),
            );
        }),
      );

      // Check final balances
      for (let i = 0; i < 10; i++) {
        const expectedBalance = depositAmount
          .mul(9)
          .add(depositAmount.sub(depositAmount.mul(10).div(10000)));
        expect(await mockUSDC.balanceOf(users[i].address)).to.be.closeTo(
          expectedBalance,
          100,
        );
      }
    });
  });
});
