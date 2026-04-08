import { expect } from "chai";
import { ethers } from "hardhat";
import {
  SampleNFT,
  RoyaltySplit,
} from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("SampleNFT", function () {
  let nft: SampleNFT;
  let royaltySplit: RoyaltySplit;
  let owner: HardhatEthersSigner;
  let minter: HardhatEthersSigner;
  let user: HardhatEthersSigner;
  let operator: HardhatEthersSigner;

  const BASE_URI = "https://api.samplechain.xyz/meta/";
  const ROYALTY_BPS = 500;
  const OPERATOR_FEE_BPS = 2000;

  beforeEach(async function () {
    [owner, minter, user, operator] = await ethers.getSigners();

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

    // Grant minter role
    const MINTER_ROLE = await nft.MINTER_ROLE();
    await nft.grantRole(MINTER_ROLE, minter.address);
  });

  // ------------------------------------------------------------------
  // Minting
  // ------------------------------------------------------------------

  describe("Minting", function () {
    it("should mint a 1-of-1 sample", async function () {
      const tx = await nft.connect(minter).mint(
        user.address,
        1, // amount
        1, // maxSupply (1-of-1)
        "QmTestCid123",
        120, // bpm
        0, // C
        0, // Oneshot
        1  // Paid
      );

      await expect(tx)
        .to.emit(nft, "SampleMinted")
        .withArgs(
          1,
          user.address,
          "QmTestCid123",
          120,
          0,
          0,
          1,
          1,
          1
        );

      expect(await nft.balanceOf(user.address, 1)).to.equal(1);
      expect(await nft["totalSupply(uint256)"](1)).to.equal(1);
    });

    it("should mint edition-based tokens", async function () {
      await nft.connect(minter).mint(
        user.address,
        10, // amount
        100, // maxSupply
        "QmEditionCid",
        140,
        5,
        1, // Loop
        0  // Free
      );

      expect(await nft.balanceOf(user.address, 1)).to.equal(10);
      expect(await nft["totalSupply(uint256)"](1)).to.equal(10);
    });

    it("should mint open editions (maxSupply = 0)", async function () {
      await nft.connect(minter).mint(
        user.address,
        50,
        0, // unlimited
        "QmOpenEdition",
        90,
        255,
        6, // Other
        0
      );

      expect(await nft.balanceOf(user.address, 1)).to.equal(50);
    });

    it("should mint additional editions via mintEdition", async function () {
      // Create token first
      await nft.connect(minter).mint(
        user.address, 5, 20, "QmCid", 100, 3, 0, 0
      );

      // Mint more editions
      await nft.connect(minter).mintEdition(minter.address, 1, 10);

      expect(await nft["totalSupply(uint256)"](1)).to.equal(15);
      expect(await nft.balanceOf(minter.address, 1)).to.equal(10);
    });

    it("should revert mintEdition exceeding maxSupply", async function () {
      await nft.connect(minter).mint(
        user.address, 5, 10, "QmCid", 100, 3, 0, 0
      );

      await expect(
        nft.connect(minter).mintEdition(user.address, 1, 6)
      ).to.be.revertedWith("SampleNFT: exceeds maxSupply");
    });

    it("should revert mint with amount > maxSupply", async function () {
      await expect(
        nft.connect(minter).mint(user.address, 5, 3, "QmCid", 100, 0, 0, 0)
      ).to.be.revertedWith("SampleNFT: amount > maxSupply");
    });

    it("should revert mint with empty CID", async function () {
      await expect(
        nft.connect(minter).mint(user.address, 1, 1, "", 100, 0, 0, 0)
      ).to.be.revertedWith("SampleNFT: empty CID");
    });

    it("should revert mint with zero amount", async function () {
      await expect(
        nft.connect(minter).mint(user.address, 0, 1, "QmCid", 100, 0, 0, 0)
      ).to.be.revertedWith("SampleNFT: amount = 0");
    });

    it("should store on-chain metadata correctly", async function () {
      await nft.connect(minter).mint(
        user.address, 1, 1, "QmMetadata", 128, 7, 3, 1
      );

      const meta = await nft.sampleMetadata(1);
      expect(meta.creator).to.equal(user.address);
      expect(meta.ipfsCid).to.equal("QmMetadata");
      expect(meta.bpm).to.equal(128);
      expect(meta.musicalKey).to.equal(7);
      expect(meta.sampleType).to.equal(3); // Texture
      expect(meta.licenseTier).to.equal(1); // Paid
      expect(meta.maxSupply).to.equal(1);
    });

    it("should auto-increment token IDs", async function () {
      await nft.connect(minter).mint(user.address, 1, 1, "QmA", 100, 0, 0, 0);
      await nft.connect(minter).mint(user.address, 1, 1, "QmB", 100, 0, 0, 0);
      await nft.connect(minter).mint(user.address, 1, 1, "QmC", 100, 0, 0, 0);

      expect(await nft.nextTokenId()).to.equal(4);
      expect(await nft.balanceOf(user.address, 1)).to.equal(1);
      expect(await nft.balanceOf(user.address, 2)).to.equal(1);
      expect(await nft.balanceOf(user.address, 3)).to.equal(1);
    });
  });

  // ------------------------------------------------------------------
  // Transfers
  // ------------------------------------------------------------------

  describe("Transfers", function () {
    beforeEach(async function () {
      await nft.connect(minter).mint(
        user.address, 5, 10, "QmCid", 120, 0, 0, 0
      );
    });

    it("should transfer tokens between accounts", async function () {
      await nft
        .connect(user)
        .safeTransferFrom(user.address, minter.address, 1, 2, "0x");

      expect(await nft.balanceOf(user.address, 1)).to.equal(3);
      expect(await nft.balanceOf(minter.address, 1)).to.equal(2);
    });

    it("should batch transfer tokens", async function () {
      // Mint a second token
      await nft.connect(minter).mint(
        user.address, 3, 5, "QmCid2", 90, 1, 1, 0
      );

      await nft
        .connect(user)
        .safeBatchTransferFrom(
          user.address,
          minter.address,
          [1, 2],
          [2, 1],
          "0x"
        );

      expect(await nft.balanceOf(user.address, 1)).to.equal(3);
      expect(await nft.balanceOf(minter.address, 1)).to.equal(2);
      expect(await nft.balanceOf(user.address, 2)).to.equal(2);
      expect(await nft.balanceOf(minter.address, 2)).to.equal(1);
    });
  });

  // ------------------------------------------------------------------
  // Access Control
  // ------------------------------------------------------------------

  describe("Access Control", function () {
    it("should revert mint from non-minter", async function () {
      await expect(
        nft.connect(user).mint(user.address, 1, 1, "QmCid", 100, 0, 0, 0)
      ).to.be.reverted;
    });

    it("should allow admin to grant minter role", async function () {
      const MINTER_ROLE = await nft.MINTER_ROLE();
      await nft.connect(owner).grantRole(MINTER_ROLE, user.address);

      await expect(
        nft.connect(user).mint(user.address, 1, 1, "QmCid", 100, 0, 0, 0)
      ).to.not.be.reverted;
    });

    it("should allow admin to revoke minter role", async function () {
      const MINTER_ROLE = await nft.MINTER_ROLE();
      await nft.connect(owner).revokeRole(MINTER_ROLE, minter.address);

      await expect(
        nft.connect(minter).mint(user.address, 1, 1, "QmCid", 100, 0, 0, 0)
      ).to.be.reverted;
    });
  });

  // ------------------------------------------------------------------
  // Pause
  // ------------------------------------------------------------------

  describe("Pausable", function () {
    it("should pause and prevent minting", async function () {
      await nft.connect(owner).pause();

      await expect(
        nft.connect(minter).mint(user.address, 1, 1, "QmCid", 100, 0, 0, 0)
      ).to.be.revertedWithCustomError(nft, "EnforcedPause");
    });

    it("should pause and prevent transfers", async function () {
      await nft.connect(minter).mint(user.address, 1, 1, "QmCid", 100, 0, 0, 0);
      await nft.connect(owner).pause();

      await expect(
        nft.connect(user).safeTransferFrom(user.address, minter.address, 1, 1, "0x")
      ).to.be.revertedWithCustomError(nft, "EnforcedPause");
    });

    it("should unpause and allow operations", async function () {
      await nft.connect(owner).pause();
      await nft.connect(owner).unpause();

      await expect(
        nft.connect(minter).mint(user.address, 1, 1, "QmCid", 100, 0, 0, 0)
      ).to.not.be.reverted;
    });

    it("should revert pause from non-admin", async function () {
      await expect(nft.connect(user).pause()).to.be.reverted;
    });
  });

  // ------------------------------------------------------------------
  // URI
  // ------------------------------------------------------------------

  describe("Metadata URI", function () {
    it("should return correct URI for token", async function () {
      await nft.connect(minter).mint(user.address, 1, 1, "QmCid", 100, 0, 0, 0);
      expect(await nft.uri(1)).to.equal(BASE_URI + "1");
    });

    it("should revert URI for nonexistent token", async function () {
      await expect(nft.uri(999)).to.be.revertedWith(
        "SampleNFT: nonexistent token"
      );
    });

    it("should allow admin to update base URI", async function () {
      await nft.connect(minter).mint(user.address, 1, 1, "QmCid", 100, 0, 0, 0);
      const newURI = "https://new.api.xyz/meta/";
      await nft.connect(owner).setBaseURI(newURI);
      expect(await nft.uri(1)).to.equal(newURI + "1");
    });
  });

  // ------------------------------------------------------------------
  // ERC-2981 Royalty
  // ------------------------------------------------------------------

  describe("ERC-2981 Royalty", function () {
    it("should return correct royalty info", async function () {
      await nft.connect(minter).mint(user.address, 1, 1, "QmCid", 100, 0, 0, 0);
      const salePrice = ethers.parseEther("1");
      const [receiver, amount] = await nft.royaltyInfo(1, salePrice);

      expect(receiver).to.equal(await royaltySplit.getAddress());
      expect(amount).to.equal(salePrice * BigInt(ROYALTY_BPS) / 10000n);
    });

    it("should support ERC-2981 interface", async function () {
      // ERC-2981 interface ID = 0x2a55205a
      expect(await nft.supportsInterface("0x2a55205a")).to.be.true;
    });

    it("should support ERC-1155 interface", async function () {
      // ERC-1155 interface ID = 0xd9b67a26
      expect(await nft.supportsInterface("0xd9b67a26")).to.be.true;
    });
  });
});
