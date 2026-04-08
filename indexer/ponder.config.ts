import { createConfig } from "@ponder/core";
import { http } from "viem";
import { SampleNFTAbi } from "./abis/SampleNFT";
import { SampleMarketplaceAbi } from "./abis/SampleMarketplace";

export default createConfig({
  networks: {
    baseSepolia: {
      chainId: 84532,
      transport: http(process.env.PONDER_RPC_URL_BASE_SEPOLIA),
    },
    base: {
      chainId: 8453,
      transport: http(process.env.PONDER_RPC_URL_BASE),
    },
  },
  contracts: {
    SampleNFT: {
      network: "baseSepolia",
      abi: SampleNFTAbi,
      address: process.env.SAMPLE_NFT_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.START_BLOCK || 0),
    },
    SampleMarketplace: {
      network: "baseSepolia",
      abi: SampleMarketplaceAbi,
      address: process.env.SAMPLE_MARKETPLACE_ADDRESS as `0x${string}`,
      startBlock: Number(process.env.START_BLOCK || 0),
    },
  },
});
