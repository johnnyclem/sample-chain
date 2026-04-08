import type { FastifyInstance } from 'fastify';
import { ethers } from 'ethers';
import { query } from '../db/index.js';
import { config } from '../config.js';

let provider: ethers.JsonRpcProvider | null = null;

function getProvider(): ethers.JsonRpcProvider {
  if (!provider) {
    provider = new ethers.JsonRpcProvider(config.ethRpcUrl);
  }
  return provider;
}

export async function registerWalletRoutes(fastify: FastifyInstance): Promise<void> {
  /** GET /api/wallet/balance/:address - on-chain balance info */
  fastify.get<{
    Params: { address: string };
  }>('/api/wallet/balance/:address', {
    schema: {
      params: {
        type: 'object',
        required: ['address'],
        properties: {
          address: { type: 'string', pattern: '^0x[a-fA-F0-9]{40}$' },
        },
      },
    },
  }, async (request, reply) => {
    const address = request.params.address.toLowerCase();

    try {
      const rpcProvider = getProvider();
      const balanceWei = await rpcProvider.getBalance(address);

      return reply.send({
        address,
        balance_wei: balanceWei.toString(),
        balance_eth: ethers.formatEther(balanceWei),
      });
    } catch (err) {
      fastify.log.error(err, 'Failed to fetch on-chain balance');
      return reply.status(502).send({
        error: 'RPC error',
        message: 'Failed to fetch balance from the blockchain',
      });
    }
  });

  /** GET /api/wallet/earnings/:address - creator earnings aggregation */
  fastify.get<{
    Params: { address: string };
  }>('/api/wallet/earnings/:address', {
    schema: {
      params: {
        type: 'object',
        required: ['address'],
        properties: {
          address: { type: 'string', pattern: '^0x[a-fA-F0-9]{40}$' },
        },
      },
    },
  }, async (request, reply) => {
    const address = request.params.address.toLowerCase();

    const earningsResult = await query<{
      total_earnings_wei: string;
      total_sales: string;
      unique_buyers: string;
    }>(
      `SELECT
         COALESCE(SUM(price_wei), 0)::TEXT AS total_earnings_wei,
         COUNT(*)::TEXT AS total_sales,
         COUNT(DISTINCT buyer_address)::TEXT AS unique_buyers
       FROM sales
       WHERE seller_address = $1`,
      [address],
    );

    const row = earningsResult.rows[0];

    // Recent earnings by month (last 12 months)
    const monthlyResult = await query<{
      month: string;
      earnings_wei: string;
      sale_count: string;
    }>(
      `SELECT
         TO_CHAR(created_at, 'YYYY-MM') AS month,
         SUM(price_wei)::TEXT AS earnings_wei,
         COUNT(*)::TEXT AS sale_count
       FROM sales
       WHERE seller_address = $1
         AND created_at >= NOW() - INTERVAL '12 months'
       GROUP BY TO_CHAR(created_at, 'YYYY-MM')
       ORDER BY month DESC`,
      [address],
    );

    // Top-selling samples
    const topSamplesResult = await query<{
      token_id: number;
      title: string;
      total_wei: string;
      sale_count: string;
    }>(
      `SELECT
         sl.token_id,
         s.title,
         SUM(sl.price_wei)::TEXT AS total_wei,
         COUNT(*)::TEXT AS sale_count
       FROM sales sl
       JOIN samples s ON sl.token_id = s.token_id
       WHERE sl.seller_address = $1
       GROUP BY sl.token_id, s.title
       ORDER BY SUM(sl.price_wei) DESC
       LIMIT 10`,
      [address],
    );

    return reply.send({
      address,
      total_earnings_wei: row?.total_earnings_wei ?? '0',
      total_earnings_eth: ethers.formatEther(row?.total_earnings_wei ?? '0'),
      total_sales: parseInt(row?.total_sales ?? '0', 10),
      unique_buyers: parseInt(row?.unique_buyers ?? '0', 10),
      monthly: monthlyResult.rows,
      top_samples: topSamplesResult.rows,
    });
  });
}
