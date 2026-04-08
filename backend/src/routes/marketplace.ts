import type { FastifyInstance } from 'fastify';
import { query } from '../db/index.js';
import type { Sample, Sale, PaginatedResponse } from '../types.js';

export async function registerMarketplaceRoutes(fastify: FastifyInstance): Promise<void> {
  /** GET /api/marketplace/listings - active listings */
  fastify.get<{
    Querystring: { page?: number; limit?: number; sort_by?: string };
  }>('/api/marketplace/listings', {
    schema: {
      querystring: {
        type: 'object',
        properties: {
          page: { type: 'number', minimum: 1, default: 1 },
          limit: { type: 'number', minimum: 1, maximum: 100, default: 20 },
          sort_by: { type: 'string', enum: ['price_asc', 'price_desc', 'newest', 'popular'] },
        },
      },
    },
  }, async (request, reply) => {
    const { page = 1, limit = 20, sort_by = 'newest' } = request.query;
    const offset = (page - 1) * limit;

    const sortMap: Record<string, string> = {
      price_asc: 's.price_wei ASC',
      price_desc: 's.price_wei DESC',
      newest: 's.created_at DESC',
      popular: 'sale_count DESC',
    };
    const orderBy = sortMap[sort_by] ?? 's.created_at DESC';

    // Active listings: samples where edition_count < edition_limit (or edition_limit is null = unlimited)
    const countResult = await query<{ count: string }>(
      `SELECT COUNT(*) as count FROM samples
       WHERE price_wei > 0
         AND (edition_limit IS NULL OR edition_count < edition_limit)`,
    );
    const total = parseInt(countResult.rows[0]?.count ?? '0', 10);

    const dataResult = await query<Sample & { sale_count: string; creator_name: string | null }>(
      `SELECT s.*,
              c.display_name as creator_name,
              (SELECT COUNT(*) FROM sales sl WHERE sl.token_id = s.token_id) AS sale_count
       FROM samples s
       LEFT JOIN creators c ON s.creator_address = c.address
       WHERE s.price_wei > 0
         AND (s.edition_limit IS NULL OR s.edition_count < s.edition_limit)
       ORDER BY ${orderBy}
       LIMIT $1 OFFSET $2`,
      [limit, offset],
    );

    const response: PaginatedResponse<Sample> = {
      data: dataResult.rows,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };

    return reply.send(response);
  });

  /** GET /api/marketplace/sales/recent - recent sales */
  fastify.get<{
    Querystring: { limit?: number };
  }>('/api/marketplace/sales/recent', {
    schema: {
      querystring: {
        type: 'object',
        properties: {
          limit: { type: 'number', minimum: 1, maximum: 50, default: 10 },
        },
      },
    },
  }, async (request, reply) => {
    const { limit = 10 } = request.query;

    const result = await query<Sale & { sample_title: string; creator_name: string | null }>(
      `SELECT sl.*,
              s.title as sample_title,
              c.display_name as creator_name
       FROM sales sl
       JOIN samples s ON sl.token_id = s.token_id
       LEFT JOIN creators c ON s.creator_address = c.address
       ORDER BY sl.created_at DESC
       LIMIT $1`,
      [limit],
    );

    return reply.send({ data: result.rows });
  });
}
