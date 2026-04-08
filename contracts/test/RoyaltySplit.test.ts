import { expect } from "chai";
import { ethers } from "hardhat";
import { RoyaltySplit } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("RoyaltySplit", function () {
  let royaltySplit: RoyaltySplit;
  let owner: HardhatEthersSigner;
  let operator: HardhatEthersSigner;
  let creator: HardhatEthersSigner;
  let other: HardhatEthersSigner;

  const ROYALTY_BPS = 500; // 5%
  const OPERATOR_FEE_BPS = 2000; // 20% of royalty

  beforeEach(async function () {
    [owner, operator, creator, other] = await ethers.getSigners();

    const Factory = await ethers.getContractFactory("RoyaltySplit");
    royaltySplit = await Factory.deploy(
      operator.address,
      ROYALTY_BPS,
      OPERATOR_FEE_BPS
    );
    await royaltySplit.waitForDeployment();

    // Register a token creator (owner is the contract owner)
    await royaltySplit.connect(owner).registerCreator(1, creator.address);
  });

  // ------------------------------------------------------------------
  // Deployment
  // ------------------------------------------------------------------

  describe("Deployment", function () {
    it("should set immutable parameters correctly", async function () {
      expect(await royaltySplit.royaltyBps()).to.equal(ROYALTY_BPS);
      expect(await royaltySplit.operatorFeeBps()).to.equal(OPERATOR_FEE_BPS);
      expect(await royaltySplit.operator()).to.equal(operator.address);
    });

    it("should revert with zero operator address", async function () {
      const Factory = await ethers.getContractFactory("RoyaltySplit");
      await expect(
        Factory.deploy(ethers.ZeroAddress, ROYALTY_BPS, OPERATOR_FEE_BPS)
      ).to.be.revertedWith("RoyaltySplit: zero operator");
    });

    it("should revert with royaltyBps > 10000", async function () {
      const Factory = await ethers.getContractFactory("RoyaltySplit");
      await expect(
        Factory.deploy(operator.address, 10001, OPERATOR_FEE_BPS)
      ).to.be.revertedWith("RoyaltySplit: royalty > 100%");
    });

    it("should revert with operatorFeeBps > 10000", async function () {
      const Factory = await ethers.getContractFactory("RoyaltySplit");
      await expect(
        Factory.deploy(operator.address, ROYALTY_BPS, 10001)
      ).to.be.revertedWith("RoyaltySplit: opFee > 100%");
    });
  });

  // ------------------------------------------------------------------
  // EIP-2981
  // ------------------------------------------------------------------

  describe("royaltyInfo (EIP-2981)", function () {
    it("should return correct royalty amount", async function () {
      const salePrice = ethers.parseEther("1");
      const [receiver, amount] = await royaltySplit.royaltyInfo(1, salePrice);

      expect(receiver).to.equal(await royaltySplit.getAddress());
      // 5% of 1 ETH = 0.05 ETH
      expect(amount).to.equal(ethers.parseEther("0.05"));
    });

    it("should return zero royalty for zero price", async function () {
      const [, amount] = await royaltySplit.royaltyInfo(1, 0);
      expect(amount).to.equal(0);
    });
  });

  // ------------------------------------------------------------------
  // Creator registration
  // ------------------------------------------------------------------

  describe("Creator registration", function () {
    it("should register a creator", async function () {
      await royaltySplit.connect(owner).registerCreator(42, other.address);
      expect(await royaltySplit.tokenCreators(42)).to.equal(other.address);
    });

    it("should emit CreatorRegistered event", async function () {
      await expect(
        royaltySplit.connect(owner).registerCreator(42, other.address)
      )
        .to.emit(royaltySplit, "CreatorRegistered")
        .withArgs(42, other.address);
    });

    it("should revert when non-owner registers", async function () {
      await expect(
        royaltySplit.connect(other).registerCreator(42, other.address)
      ).to.be.revertedWithCustomError(royaltySplit, "OwnableUnauthorizedAccount");
    });

    it("should revert with zero creator", async function () {
      await expect(
        royaltySplit.connect(owner).registerCreator(42, ethers.ZeroAddress)
      ).to.be.revertedWith("RoyaltySplit: zero creator");
    });
  });

  // ------------------------------------------------------------------
  // Receiving royalty
  // ------------------------------------------------------------------

  describe("receiveRoyalty", function () {
    it("should split royalty between operator and creator", async function () {
      const royaltyAmount = ethers.parseEther("0.05");

      await royaltySplit.receiveRoyalty(1, { value: royaltyAmount });

      // Operator gets 20% of 0.05 = 0.01
      const expectedOpShare = ethers.parseEther("0.01");
      // Creator gets 80% of 0.05 = 0.04
      const expectedCreatorShare = ethers.parseEther("0.04");

      expect(await royaltySplit.operatorBalance()).to.equal(expectedOpShare);
      expect(await royaltySplit.balances(creator.address)).to.equal(
        expectedCreatorShare
      );
    });

    it("should emit RoyaltyReceived event", async function () {
      const amt = ethers.parseEther("0.1");
      await expect(royaltySplit.receiveRoyalty(1, { value: amt }))
        .to.emit(royaltySplit, "RoyaltyReceived")
        .withArgs(1, amt, creator.address);
    });

    it("should revert with zero value", async function () {
      await expect(
        royaltySplit.receiveRoyalty(1, { value: 0 })
      ).to.be.revertedWith("RoyaltySplit: no value");
    });

    it("should revert for unregistered token", async function () {
      await expect(
        royaltySplit.receiveRoyalty(999, { value: ethers.parseEther("0.01") })
      ).to.be.revertedWith("RoyaltySplit: unknown token");
    });
  });

  // ------------------------------------------------------------------
  // Withdrawals
  // ------------------------------------------------------------------

  describe("Withdrawals", function () {
    beforeEach(async function () {
      // Send some royalty
      await royaltySplit.receiveRoyalty(1, {
        value: ethers.parseEther("1"),
      });
    });

    it("should allow creator to withdraw", async function () {
      const balBefore = await ethers.provider.getBalance(creator.address);

      const tx = await royaltySplit.connect(creator).withdraw();
      const receipt = await tx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;

      const balAfter = await ethers.provider.getBalance(creator.address);
      const expectedShare = ethers.parseEther("0.8"); // 80% of 1 ETH

      expect(balAfter - balBefore + gasUsed).to.equal(expectedShare);
    });

    it("should emit Withdrawn event", async function () {
      await expect(royaltySplit.connect(creator).withdraw())
        .to.emit(royaltySplit, "Withdrawn")
        .withArgs(creator.address, ethers.parseEther("0.8"));
    });

    it("should allow operator to withdraw", async function () {
      const balBefore = await ethers.provider.getBalance(operator.address);

      const tx = await royaltySplit.connect(operator).withdrawOperator();
      const receipt = await tx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;

      const balAfter = await ethers.provider.getBalance(operator.address);
      const expectedShare = ethers.parseEther("0.2"); // 20% of 1 ETH

      expect(balAfter - balBefore + gasUsed).to.equal(expectedShare);
    });

    it("should emit OperatorWithdrawn event", async function () {
      await expect(royaltySplit.connect(operator).withdrawOperator())
        .to.emit(royaltySplit, "OperatorWithdrawn")
        .withArgs(operator.address, ethers.parseEther("0.2"));
    });

    it("should revert withdraw with zero balance", async function () {
      await expect(
        royaltySplit.connect(other).withdraw()
      ).to.be.revertedWith("RoyaltySplit: nothing to withdraw");
    });

    it("should revert operator withdraw from non-operator", async function () {
      await expect(
        royaltySplit.connect(other).withdrawOperator()
      ).to.be.revertedWith("RoyaltySplit: not operator");
    });

    it("should revert double withdraw", async function () {
      await royaltySplit.connect(creator).withdraw();
      await expect(
        royaltySplit.connect(creator).withdraw()
      ).to.be.revertedWith("RoyaltySplit: nothing to withdraw");
    });

    it("should accumulate across multiple royalty payments", async function () {
      // Send more royalty
      await royaltySplit.receiveRoyalty(1, {
        value: ethers.parseEther("1"),
      });

      // Creator should have 0.8 + 0.8 = 1.6
      expect(await royaltySplit.balances(creator.address)).to.equal(
        ethers.parseEther("1.6")
      );
    });
  });

  // ------------------------------------------------------------------
  // Interface support
  // ------------------------------------------------------------------

  describe("supportsInterface", function () {
    it("should support ERC-2981", async function () {
      expect(await royaltySplit.supportsInterface("0x2a55205a")).to.be.true;
    });

    it("should support ERC-165", async function () {
      expect(await royaltySplit.supportsInterface("0x01ffc9a7")).to.be.true;
    });

    it("should not support random interface", async function () {
      expect(await royaltySplit.supportsInterface("0xdeadbeef")).to.be.false;
    });
  });
});
