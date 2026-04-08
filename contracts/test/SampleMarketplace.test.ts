import { expect } from "chai";
import { ethers } from "hardhat";
import {
  SampleNFT,
  RoyaltySplit,
  SampleMarketplace,
} from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("SampleMarketplace", function () {
  let nft: SampleNFT;
  let royaltySplit: RoyaltySplit;
  let marketplace: SampleMarketplace;
  let owner: HardhatEthersSigner;
  let seller: HardhatEthersSigner;
  let buyer: HardhatEthersSigner;
  let operator: HardhatEthersSigner;

  const BASE_URI = "https://api.samplechain.xyz/meta/";
  const ROYALTY_BPS = 500; // 5%
  const OPERATOR_FEE_BPS = 2000; // 20% of royalty

  beforeEach(async function () {
    [owner, seller, buyer, operator] = await ethers.getSigners();

    // Deploy RoyaltySplit
    const RoyaltySplitFactory = await ethers.getContractFactory("RoyaltySplit");
    royaltySplit = await RoyaltySplitFactory.deploy(
      operator.address,
      ROYALTY_BPS,
      OPERATOR_FEE_BPS
    );
    await royaltySplit.waitForDeployment();

    // Deploy SampleNFT
    const SampleNFTFactory = await ethers.getContractFactory("SampleNFT");
    nft = await SampleNFTFactory.deploy(
      BASE_URI,
      await royaltySplit.getAddress()
    );
    await nft.waitForDeployment();

    // Transfer RoyaltySplit ownership to NFT contract
    await royaltySplit.transferOwnership(await nft.getAddress());

    // Deploy Marketplace
    const MarketFactory = await ethers.getContractFactory("SampleMarketplace");
    marketplace = await MarketFactory.deploy(
      await nft.getAddress(),
      await royaltySplit.getAddress()
    );
    await marketplace.waitForDeployment();

    // Grant minter role to owner
    const MINTER_ROLE = await nft.MINTER_ROLE();
    await nft.grantRole(MINTER_ROLE, owner.address);

    // Mint 10 copies of token 1 to seller
    await nft.connect(owner).mint(
      seller.address,
      10,
      100,
      "QmMarketCid",
      120,
      0,
      1, // Loop
      1  // Paid
    );

    // Seller approves marketplace
    await nft
      .connect(seller)
      .setApprovalForAll(await marketplace.getAddress(), true);
  });

  // ------------------------------------------------------------------
  // Listing
  // ------------------------------------------------------------------

  describe("Listing", function () {
    it("should create a listing", async function () {
      const price = ethers.parseEther("0.1");
      const tx = await marketplace.connect(seller).list(1, 5, price);

      await expect(tx)
        .to.emit(marketplace, "SampleListed")
        .withArgs(1, seller.address, 1, 5, price);

      const listing = await marketplace.listings(1);
      expect(listing.seller).to.equal(seller.address);
      expect(listing.tokenId).to.equal(1);
      expect(listing.amount).to.equal(5);
      expect(listing.pricePerUnit).to.equal(price);
      expect(listing.active).to.be.true;
    });

    it("should create a free listing (price = 0)", async function () {
      await marketplace.connect(seller).list(1, 3, 0);
      const listing = await marketplace.listings(1);
      expect(listing.pricePerUnit).to.equal(0);
      expect(listing.active).to.be.true;
    });

    it("should revert listing with zero amount", async function () {
      await expect(
        marketplace.connect(seller).list(1, 0, ethers.parseEther("0.1"))
      ).to.be.revertedWith("Marketplace: amount = 0");
    });

    it("should revert listing without sufficient balance", async function () {
      await expect(
        marketplace.connect(seller).list(1, 100, ethers.parseEther("0.1"))
      ).to.be.revertedWith("Marketplace: insufficient balance");
    });

    it("should revert listing without approval", async function () {
      // Revoke approval
      await nft
        .connect(seller)
        .setApprovalForAll(await marketplace.getAddress(), false);

      await expect(
        marketplace.connect(seller).list(1, 5, ethers.parseEther("0.1"))
      ).to.be.revertedWith("Marketplace: not approved");
    });

    it("should auto-increment listing IDs", async function () {
      await marketplace.connect(seller).list(1, 2, ethers.parseEther("0.1"));
      await marketplace.connect(seller).list(1, 3, ethers.parseEther("0.2"));

      expect(await marketplace.nextListingId()).to.equal(3);
      expect((await marketplace.listings(1)).amount).to.equal(2);
      expect((await marketplace.listings(2)).amount).to.equal(3);
    });
  });

  // ------------------------------------------------------------------
  // Cancellation
  // ------------------------------------------------------------------

  describe("Cancellation", function () {
    beforeEach(async function () {
      await marketplace
        .connect(seller)
        .list(1, 5, ethers.parseEther("0.1"));
    });

    it("should cancel a listing", async function () {
      const tx = await marketplace.connect(seller).cancel(1);
      await expect(tx).to.emit(marketplace, "ListingCancelled").withArgs(1);

      const listing = await marketplace.listings(1);
      expect(listing.active).to.be.false;
    });

    it("should revert cancel from non-seller", async function () {
      await expect(
        marketplace.connect(buyer).cancel(1)
      ).to.be.revertedWith("Marketplace: not seller");
    });

    it("should revert cancel of inactive listing", async function () {
      await marketplace.connect(seller).cancel(1);
      await expect(
        marketplace.connect(seller).cancel(1)
      ).to.be.revertedWith("Marketplace: not active");
    });
  });

  // ------------------------------------------------------------------
  // Buying
  // ------------------------------------------------------------------

  describe("Buying", function () {
    const UNIT_PRICE = ethers.parseEther("1");

    beforeEach(async function () {
      await marketplace.connect(seller).list(1, 5, UNIT_PRICE);
    });

    it("should execute a purchase and distribute funds", async function () {
      const sellerBalBefore = await ethers.provider.getBalance(seller.address);

      const tx = await marketplace
        .connect(buyer)
        .buy(1, 2, { value: UNIT_PRICE * 2n });

      await expect(tx)
        .to.emit(marketplace, "SampleSold")
        .withArgs(1, buyer.address, 2, UNIT_PRICE * 2n);

      // Buyer should have 2 NFTs
      expect(await nft.balanceOf(buyer.address, 1)).to.equal(2);

      // Listing amount should be reduced
      const listing = await marketplace.listings(1);
      expect(listing.amount).to.equal(3);
      expect(listing.active).to.be.true;

      // Check royalty was deposited (5% of 2 ETH = 0.1 ETH)
      const royaltyAddr = await royaltySplit.getAddress();
      const royaltyBalance = await ethers.provider.getBalance(royaltyAddr);
      expect(royaltyBalance).to.equal(ethers.parseEther("0.1"));

      // Seller should have received 95% = 1.9 ETH
      const sellerBalAfter = await ethers.provider.getBalance(seller.address);
      expect(sellerBalAfter - sellerBalBefore).to.equal(
        ethers.parseEther("1.9")
      );
    });

    it("should deactivate listing when fully sold", async function () {
      await marketplace
        .connect(buyer)
        .buy(1, 5, { value: UNIT_PRICE * 5n });

      const listing = await marketplace.listings(1);
      expect(listing.amount).to.equal(0);
      expect(listing.active).to.be.false;
    });

    it("should handle free sample purchase", async function () {
      // Create free listing
      await marketplace.connect(seller).list(1, 3, 0);
      // listingId = 2 (second listing)

      await marketplace.connect(buyer).buy(2, 2, { value: 0 });
      expect(await nft.balanceOf(buyer.address, 1)).to.equal(2);
    });

    it("should revert purchase of inactive listing", async function () {
      await marketplace.connect(seller).cancel(1);
      await expect(
        marketplace.connect(buyer).buy(1, 1, { value: UNIT_PRICE })
      ).to.be.revertedWith("Marketplace: not active");
    });

    it("should revert purchase with wrong ETH amount", async function () {
      await expect(
        marketplace.connect(buyer).buy(1, 1, { value: UNIT_PRICE / 2n })
      ).to.be.revertedWith("Marketplace: wrong ETH amount");
    });

    it("should revert purchase of zero amount", async function () {
      await expect(
        marketplace.connect(buyer).buy(1, 0, { value: 0 })
      ).to.be.revertedWith("Marketplace: bad amount");
    });

    it("should revert purchase exceeding listed amount", async function () {
      await expect(
        marketplace
          .connect(buyer)
          .buy(1, 10, { value: UNIT_PRICE * 10n })
      ).to.be.revertedWith("Marketplace: bad amount");
    });

    it("should correctly split royalty between operator and creator in RoyaltySplit", async function () {
      await marketplace
        .connect(buyer)
        .buy(1, 1, { value: UNIT_PRICE });

      // Total royalty = 5% of 1 ETH = 0.05 ETH
      // Operator share = 20% of 0.05 = 0.01 ETH
      // Creator share = 80% of 0.05 = 0.04 ETH
      expect(await royaltySplit.operatorBalance()).to.equal(
        ethers.parseEther("0.01")
      );
      expect(await royaltySplit.balances(seller.address)).to.equal(
        ethers.parseEther("0.04")
      );
    });

    it("should allow creator to withdraw royalties after sale", async function () {
      await marketplace
        .connect(buyer)
        .buy(1, 1, { value: UNIT_PRICE });

      const balBefore = await ethers.provider.getBalance(seller.address);
      const tx = await royaltySplit.connect(seller).withdraw();
      const receipt = await tx.wait();
      const gasUsed = receipt!.gasUsed * receipt!.gasPrice;
      const balAfter = await ethers.provider.getBalance(seller.address);

      // Creator's royalty share = 0.04 ETH
      expect(balAfter - balBefore + gasUsed).to.equal(
        ethers.parseEther("0.04")
      );
    });
  });

  // ------------------------------------------------------------------
  // Constructor validation
  // ------------------------------------------------------------------

  describe("Constructor", function () {
    it("should revert with zero NFT address", async function () {
      const Factory = await ethers.getContractFactory("SampleMarketplace");
      await expect(
        Factory.deploy(ethers.ZeroAddress, await royaltySplit.getAddress())
      ).to.be.revertedWith("Marketplace: zero nft");
    });

    it("should revert with zero royaltySplit address", async function () {
      const Factory = await ethers.getContractFactory("SampleMarketplace");
      await expect(
        Factory.deploy(await nft.getAddress(), ethers.ZeroAddress)
      ).to.be.revertedWith("Marketplace: zero royaltySplit");
    });
  });
});
