export const SampleMarketplaceAbi = [
  {
    type: "event",
    name: "SampleListed",
    inputs: [
      { name: "tokenId", type: "uint256", indexed: true },
      { name: "seller", type: "address", indexed: true },
      { name: "price", type: "uint256", indexed: false },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "SampleSold",
    inputs: [
      { name: "tokenId", type: "uint256", indexed: true },
      { name: "seller", type: "address", indexed: true },
      { name: "buyer", type: "address", indexed: true },
      { name: "price", type: "uint256", indexed: false },
      { name: "royaltyAmount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "ListingCancelled",
    inputs: [
      { name: "tokenId", type: "uint256", indexed: true },
      { name: "seller", type: "address", indexed: true },
    ],
  },
] as const;
