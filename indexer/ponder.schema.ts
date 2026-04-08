import { onchainTable, relations } from "@ponder/core";

export const samples = onchainTable("samples", (t) => ({
  id: t.text().primaryKey(), // tokenId as string
  tokenId: t.bigint().notNull(),
  creator: t.hex().notNull(),
  ipfsCid: t.text().notNull(),
  bpm: t.integer().notNull(),
  musicalKey: t.integer().notNull(),
  sampleType: t.integer().notNull(),
  licenseTier: t.integer().notNull(),
  editionLimit: t.bigint().notNull(),
  totalMinted: t.bigint().notNull(),
  metadataUri: t.text(),
  createdAt: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
}));

export const samplesRelations = relations(samples, ({ many }) => ({
  transfers: many(transfers),
  sales: many(sales),
  listings: many(listings),
}));

export const transfers = onchainTable("transfers", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  tokenId: t.bigint().notNull(),
  from: t.hex().notNull(),
  to: t.hex().notNull(),
  amount: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
}));

export const transfersRelations = relations(transfers, ({ one }) => ({
  sample: one(samples, {
    fields: [transfers.tokenId],
    references: [samples.tokenId],
  }),
}));

export const sales = onchainTable("sales", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  tokenId: t.bigint().notNull(),
  seller: t.hex().notNull(),
  buyer: t.hex().notNull(),
  price: t.bigint().notNull(),
  royaltyAmount: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
  transactionHash: t.hex().notNull(),
}));

export const salesRelations = relations(sales, ({ one }) => ({
  sample: one(samples, {
    fields: [sales.tokenId],
    references: [samples.tokenId],
  }),
}));

export const listings = onchainTable("listings", (t) => ({
  id: t.text().primaryKey(), // tokenId-seller
  tokenId: t.bigint().notNull(),
  seller: t.hex().notNull(),
  price: t.bigint().notNull(),
  amount: t.bigint().notNull(),
  active: t.boolean().notNull(),
  createdAt: t.bigint().notNull(),
  blockNumber: t.bigint().notNull(),
}));

export const listingsRelations = relations(listings, ({ one }) => ({
  sample: one(samples, {
    fields: [listings.tokenId],
    references: [samples.tokenId],
  }),
}));

export const creators = onchainTable("creators", (t) => ({
  address: t.hex().primaryKey(),
  totalSamples: t.integer().notNull(),
  totalSales: t.bigint().notNull(),
  totalEarnings: t.bigint().notNull(),
  firstMintBlock: t.bigint().notNull(),
}));

export const creatorsRelations = relations(creators, ({ many }) => ({
  samples: many(samples),
}));
