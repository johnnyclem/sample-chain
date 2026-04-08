import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log(
    "Account balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH"
  );

  // ---- Configuration ----
  const ROYALTY_BPS = 500; // 5% total royalty
  const OPERATOR_FEE_BPS = 2000; // 20% of royalty goes to operator
  const BASE_URI = "https://api.samplechain.xyz/meta/";

  // ---- 1. Deploy RoyaltySplit ----
  console.log("\n1. Deploying RoyaltySplit...");
  const RoyaltySplit = await ethers.getContractFactory("RoyaltySplit");
  const royaltySplit = await RoyaltySplit.deploy(
    deployer.address, // operator
    ROYALTY_BPS,
    OPERATOR_FEE_BPS
  );
  await royaltySplit.waitForDeployment();
  const royaltySplitAddr = await royaltySplit.getAddress();
  console.log("   RoyaltySplit deployed to:", royaltySplitAddr);

  // ---- 2. Deploy SampleNFT ----
  console.log("\n2. Deploying SampleNFT...");
  const SampleNFT = await ethers.getContractFactory("SampleNFT");
  const sampleNFT = await SampleNFT.deploy(BASE_URI, royaltySplitAddr);
  await sampleNFT.waitForDeployment();
  const sampleNFTAddr = await sampleNFT.getAddress();
  console.log("   SampleNFT deployed to:", sampleNFTAddr);

  // ---- 3. Transfer RoyaltySplit ownership to SampleNFT ----
  console.log("\n3. Transferring RoyaltySplit ownership to SampleNFT...");
  const tx = await royaltySplit.transferOwnership(sampleNFTAddr);
  await tx.wait();
  console.log("   Ownership transferred.");

  // ---- 4. Deploy SampleMarketplace ----
  console.log("\n4. Deploying SampleMarketplace...");
  const SampleMarketplace = await ethers.getContractFactory(
    "SampleMarketplace"
  );
  const marketplace = await SampleMarketplace.deploy(
    sampleNFTAddr,
    royaltySplitAddr
  );
  await marketplace.waitForDeployment();
  const marketplaceAddr = await marketplace.getAddress();
  console.log("   SampleMarketplace deployed to:", marketplaceAddr);

  // ---- Summary ----
  console.log("\n========== Deployment Summary ==========");
  console.log("RoyaltySplit:      ", royaltySplitAddr);
  console.log("SampleNFT:         ", sampleNFTAddr);
  console.log("SampleMarketplace: ", marketplaceAddr);
  console.log("=========================================\n");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
