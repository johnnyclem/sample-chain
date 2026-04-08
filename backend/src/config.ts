import dotenv from 'dotenv';
import path from 'node:path';

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

function requireEnv(key: string, fallback?: string): string {
  const value = process.env[key] ?? fallback;
  if (value === undefined) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

export const config = {
  port: parseInt(requireEnv('PORT', '3001'), 10),
  host: requireEnv('HOST', '0.0.0.0'),
  nodeEnv: requireEnv('NODE_ENV', 'development'),

  databaseUrl: requireEnv('DATABASE_URL', 'postgresql://samplechain:samplechain@localhost:5432/samplechain'),

  redisUrl: requireEnv('REDIS_URL', 'redis://localhost:6379'),

  jwtSecret: requireEnv('JWT_SECRET', 'dev-secret-change-me'),

  ethRpcUrl: requireEnv('ETH_RPC_URL', 'http://localhost:8545'),

  ipfsGatewayUrl: requireEnv('IPFS_GATEWAY_URL', 'https://gateway.pinata.cloud/ipfs'),

  corsOrigin: requireEnv('CORS_ORIGIN', 'http://localhost:3000'),

  rateLimitMax: parseInt(requireEnv('RATE_LIMIT_MAX', '100'), 10),
  rateLimitWindowMs: parseInt(requireEnv('RATE_LIMIT_WINDOW_MS', '60000'), 10),

  maxUploadSizeMb: parseInt(requireEnv('MAX_UPLOAD_SIZE_MB', '50'), 10),
  maxSampleDurationSeconds: parseInt(requireEnv('MAX_SAMPLE_DURATION_SECONDS', '30'), 10),
} as const;
