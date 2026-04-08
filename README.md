# SampleChain

Open-source, blockchain-native audio sample marketplace delivered as a macOS AUv3 plugin. Every sample is minted as an on-chain token (ERC-1155 on Base L2) with immutable provenance and automatic royalty distribution.

## Architecture

```
contracts/    — Solidity smart contracts (Hardhat, Base L2)
backend/      — REST API server (Node.js, Fastify, PostgreSQL)
plugin/       — macOS AUv3 plugin + standalone app (Swift, SwiftUI)
indexer/      — On-chain event indexer (Ponder)
```

## Quick Start

### Smart Contracts
```bash
cd contracts
npm install
npx hardhat compile
npx hardhat test
```

### Backend API
```bash
cd backend
npm install
# Start dependencies
docker compose up postgres redis -d
# Run migrations
psql $DATABASE_URL -f src/db/schema.sql
# Start server
npm run dev
```

### macOS Plugin (requires macOS + Xcode 15.4+)
```bash
cd plugin
swift build
swift test
```

### Indexer
```bash
cd indexer
npm install
npm run dev
```

## Development with Docker
```bash
docker compose up
```

## Tech Stack

- **Plugin**: Swift 6, AUv3, AVAudioEngine, SwiftUI, Accelerate
- **Blockchain**: Solidity, ERC-1155, EIP-2981, Base L2, Hardhat
- **Backend**: Node.js (Fastify), PostgreSQL, BullMQ, Redis
- **Storage**: IPFS (Pinata), Cloudflare R2 (CDN)
- **Indexer**: Ponder
- **Auth**: SIWE (Sign In With Ethereum)

## License

MIT
