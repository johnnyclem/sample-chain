import type { FastifyInstance } from 'fastify';
import { query } from '../db/index.js';
import { getAuthAddress } from '../middleware/auth.js';
import type { Creator, Sample, PaginatedResponse } from '../types.js';

export async function registerCreatorRoutes(fastify: FastifyInstance): Promise<void> {
  /** GET /api/creators/:address - creator profile */
  fastify.get<{
    Params: { address: string };
  }>('/api/creators/:address', {
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

    const result = await query<Creator & { sample_count: string; total_sales: string }>(
      `SELECT c.*,
              (SELECT COUNT(*) FROM samples s WHERE s.creator_address = c.address) AS sample_count,
              (SELECT COALESCE(SUM(sl.price_wei), 0) FROM sales sl WHERE sl.seller_address = c.address) AS total_sales
       FROM creators c
       WHERE c.address = $1`,
      [address],
    );

    if (result.rows.length === 0) {
      return reply.status(404).send({ error: 'Creator not found' });
    }

    return reply.send(result.rows[0]);
  });

  /** GET /api/creators/:address/samples - creator's sample catalog */
  fastify.get<{
    Params: { address: string };
    Querystring: { page?: number; limit?: number };
  }>('/api/creators/:address/samples', {
    schema: {
      params: {
        type: 'object',
        required: ['address'],
        properties: {
          address: { type: 'string', pattern: '^0x[a-fA-F0-9]{40}$' },
        },
      },
      querystring: {
        type: 'object',
        properties: {
          page: { type: 'number', minimum: 1, default: 1 },
          limit: { type: 'number', minimum: 1, maximum: 100, default: 20 },
        },
      },
    },
  }, async (request, reply) => {
    const address = request.params.address.toLowerCase();
    const { page = 1, limit = 20 } = request.query;
    const offset = (page - 1) * limit;

    const countResult = await query<{ count: string }>(
      `SELECT COUNT(*) as count FROM samples WHERE creator_address = $1`,
      [address],
    );
    const total = parseInt(countResult.rows[0]?.count ?? '0', 10);

    const dataResult = await query<Sample>(
      `SELECT * FROM samples WHERE creator_address = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
      [address, limit, offset],
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

  /** PUT /api/creators/:address - update profile (authenticated, must be own address) */
  fastify.put<{
    Params: { address: string };
    Body: { display_name?: string; bio?: string; avatar_url?: string };
  }>('/api/creators/:address', {
    preHandler: [fastify.authenticate],
    schema: {
      params: {
        type: 'object',
        required: ['address'],
        properties: {
          address: { type: 'string', pattern: '^0x[a-fA-F0-9]{40}$' },
        },
      },
      body: {
        type: 'object',
        properties: {
          display_name: { type: 'string', maxLength: 100 },
          bio: { type: 'string', maxLength: 2000 },
          avatar_url: { type: 'string', format: 'uri' },
        },
      },
    },
  }, async (request, reply) => {
    const address = request.params.address.toLowerCase();
    const authAddress = getAuthAddress(request);

    if (authAddress !== address) {
      return reply.status(403).send({ error: 'Forbidden', message: 'You can only update your own profile' });
    }

    const { display_name, bio, avatar_url } = request.body;

    const result = await query<Creator>(
      `INSERT INTO creators (address, display_name, bio, avatar_url)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (address) DO UPDATE
       SET display_name = COALESCE($2, creators.display_name),
           bio = COALESCE($3, creators.bio),
           avatar_url = COALESCE($4, creators.avatar_url)
       RETURNING *`,
      [address, display_name ?? null, bio ?? null, avatar_url ?? null],
    );

    return reply.send(result.rows[0]);
  });
}
