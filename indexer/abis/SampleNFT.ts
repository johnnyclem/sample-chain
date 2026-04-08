export const SampleNFTAbi = [
  {
    type: "event",
    name: "SampleMinted",
    inputs: [
      { name: "tokenId", type: "uint256", indexed: true },
      { name: "creator", type: "address", indexed: true },
      { name: "ipfsCid", type: "string", indexed: false },
      { name: "bpm", type: "uint16", indexed: false },
      { name: "musicalKey", type: "uint8", indexed: false },
      { name: "sampleType", type: "uint8", indexed: false },
      { name: "licenseTier", type: "uint8", indexed: false },
      { name: "editionLimit", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "TransferSingle",
    inputs: [
      { name: "operator", type: "address", indexed: true },
      { name: "from", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "id", type: "uint256", indexed: false },
      { name: "value", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "TransferBatch",
    inputs: [
      { name: "operator", type: "address", indexed: true },
      { name: "from", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "ids", type: "uint256[]", indexed: false },
      { name: "values", type: "uint256[]", indexed: false },
    ],
  },
  {
    type: "event",
    name: "URI",
    inputs: [
      { name: "value", type: "string", indexed: false },
      { name: "id", type: "uint256", indexed: true },
    ],
  },
] as const;
