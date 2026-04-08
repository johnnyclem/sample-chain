import { ponder } from "@/generated";
import * as schema from "../ponder.schema";

// Index SampleMinted events
ponder.on("SampleNFT:SampleMinted", async ({ event, context }) => {
  const { db } = context;
  const { tokenId, creator, ipfsCid, bpm, musicalKey, sampleType, licenseTier, editionLimit } =
    event.args;

  // Upsert creator
  await db
    .insert(schema.creators)
    .values({
      address: creator,
      totalSamples: 1,
      totalSales: 0n,
      totalEarnings: 0n,
      firstMintBlock: event.block.number,
    })
    .onConflictDoUpdate((row) => ({
      totalSamples: row.totalSamples + 1,
    }));

  // Insert sample
  await db.insert(schema.samples).values({
    id: tokenId.toString(),
    tokenId,
    creator,
    ipfsCid,
    bpm: Number(bpm),
    musicalKey: Number(musicalKey),
    sampleType: Number(sampleType),
    licenseTier: Number(licenseTier),
    editionLimit,
    totalMinted: 1n,
    metadataUri: null,
    createdAt: event.block.timestamp,
    blockNumber: event.block.number,
    transactionHash: event.transaction.hash,
  });
});

// Index TransferSingle events
ponder.on("SampleNFT:TransferSingle", async ({ event, context }) => {
  const { db } = context;
  const { from, to, id: tokenId, value } = event.args;

  await db.insert(schema.transfers).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    tokenId,
    from,
    to,
    amount: value,
    blockNumber: event.block.number,
    timestamp: event.block.timestamp,
    transactionHash: event.transaction.hash,
  });

  // Update edition count for mints (from zero address)
  if (from === "0x0000000000000000000000000000000000000000") {
    await db
      .update(schema.samples, { id: tokenId.toString() })
      .set((row) => ({
        totalMinted: row.totalMinted + value,
      }));
  }
});

// Index SampleSold events from marketplace
ponder.on("SampleMarketplace:SampleSold", async ({ event, context }) => {
  const { db } = context;
  const { tokenId, seller, buyer, price, royaltyAmount } = event.args;

  // Record sale
  await db.insert(schema.sales).values({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    tokenId,
    seller,
    buyer,
    price,
    royaltyAmount,
    blockNumber: event.block.number,
    timestamp: event.block.timestamp,
    transactionHash: event.transaction.hash,
  });

  // Update creator earnings
  const sample = await db.find(schema.samples, { id: tokenId.toString() });
  if (sample) {
    await db
      .update(schema.creators, { address: sample.creator })
      .set((row) => ({
        totalSales: row.totalSales + 1n,
        totalEarnings: row.totalEarnings + royaltyAmount,
      }));
  }

  // Mark listing as inactive
  await db
    .update(schema.listings, { id: `${tokenId.toString()}-${seller}` })
    .set({ active: false });
});

// Index SampleListed events
ponder.on("SampleMarketplace:SampleListed", async ({ event, context }) => {
  const { db } = context;
  const { tokenId, seller, price, amount } = event.args;

  await db
    .insert(schema.listings)
    .values({
      id: `${tokenId.toString()}-${seller}`,
      tokenId,
      seller,
      price,
      amount,
      active: true,
      createdAt: event.block.timestamp,
      blockNumber: event.block.number,
    })
    .onConflictDoUpdate({
      price,
      amount,
      active: true,
    });
});

// Index ListingCancelled events
ponder.on("SampleMarketplace:ListingCancelled", async ({ event, context }) => {
  const { db } = context;
  const { tokenId, seller } = event.args;

  await db
    .update(schema.listings, { id: `${tokenId.toString()}-${seller}` })
    .set({ active: false });
});
