import type { FastifyInstance } from 'fastify';
import { query } from '../db/index.js';
import { getAuthAddress } from '../middleware/auth.js';
import type { Sample, SampleFilterParams, PaginatedResponse } from '../types.js';
import { config } from '../config.js';

export async function registerSampleRoutes(fastify: FastifyInstance): Promise<void> {
  /** GET /api/samples - paginated, filterable sample catalog */
  fastify.get<{
    Querystring: Partial<SampleFilterParams>;
  }>('/api/samples', {
    schema: {
      querystring: {
        type: 'object',
        properties: {
          genre: { type: 'string' },
          instrument_type: { type: 'string' },
          bpm_min: { type: 'number' },
          bpm_max: { type: 'number' },
          key: { type: 'string' },
          sample_type: { type: 'string', enum: ['one-shot', 'loop', 'stem', 'full-track'] },
          license_tier: { type: 'string', enum: ['free', 'basic', 'premium', 'exclusive'] },
          creator: { type: 'string' },
          sort_by: { type: 'string', enum: ['created_at', 'price', 'title', 'bpm'] },
          page: { type: 'number', minimum: 1, default: 1 },
          limit: { type: 'number', minimum: 1, maximum: 100, default: 20 },
        },
      },
    },
  }, async (request, reply) => {
    const {
      genre,
      instrument_type,
      bpm_min,
      bpm_max,
      key,
      sample_type,
      license_tier,
      creator,
      sort_by = 'created_at',
      page = 1,
      limit = 20,
    } = request.query;

    const conditions: string[] = [];
    const params: unknown[] = [];
    let paramIndex = 1;

    if (genre) {
      conditions.push(`s.genre = $${paramIndex++}`);
      params.push(genre);
    }
    if (instrument_type) {
      conditions.push(`s.instrument_type = $${paramIndex++}`);
      params.push(instrument_type);
    }
    if (bpm_min !== undefined) {
      conditions.push(`s.bpm >= $${paramIndex++}`);
      params.push(bpm_min);
    }
    if (bpm_max !== undefined) {
      conditions.push(`s.bpm <= $${paramIndex++}`);
      params.push(bpm_max);
    }
    if (key) {
      conditions.push(`s.musical_key = $${paramIndex++}`);
      params.push(key);
    }
    if (sample_type) {
      conditions.push(`s.sample_type = $${paramIndex++}`);
      params.push(sample_type);
    }
    if (license_tier) {
      conditions.push(`s.license_tier = $${paramIndex++}`);
      params.push(license_tier);
    }
    if (creator) {
      conditions.push(`s.creator_address = $${paramIndex++}`);
      params.push(creator.toLowerCase());
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const sortMap: Record<string, string> = {
      created_at: 's.created_at DESC',
      price: 's.price_wei ASC',
      title: 's.title ASC',
      bpm: 's.bpm ASC NULLS LAST',
    };
    const orderBy = sortMap[sort_by] ?? 's.created_at DESC';

    const offset = (page - 1) * limit;

    // Count query
    const countResult = await query<{ count: string }>(
      `SELECT COUNT(*) as count FROM samples s ${whereClause}`,
      params,
    );
    const total = parseInt(countResult.rows[0]?.count ?? '0', 10);

    // Data query
    const dataResult = await query<Sample>(
      `SELECT s.* FROM samples s ${whereClause} ORDER BY ${orderBy} LIMIT $${paramIndex++} OFFSET $${paramIndex++}`,
      [...params, limit, offset],
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

  /** GET /api/samples/search - full-text search */
  fastify.get<{
    Querystring: { q: string; page?: number; limit?: number };
  }>('/api/samples/search', {
    schema: {
      querystring: {
        type: 'object',
        required: ['q'],
        properties: {
          q: { type: 'string', minLength: 1 },
          page: { type: 'number', minimum: 1, default: 1 },
          limit: { type: 'number', minimum: 1, maximum: 100, default: 20 },
        },
      },
    },
  }, async (request, reply) => {
    const { q, page = 1, limit = 20 } = request.query;
    const offset = (page - 1) * limit;

    const tsQuery = q.trim().split(/\s+/).join(' & ');

    const countResult = await query<{ count: string }>(
      `SELECT COUNT(*) as count FROM samples WHERE search_vector @@ to_tsquery('english', $1)`,
      [tsQuery],
    );
    const total = parseInt(countResult.rows[0]?.count ?? '0', 10);

    const dataResult = await query<Sample & { rank: number }>(
      `SELECT *, ts_rank(search_vector, to_tsquery('english', $1)) AS rank
       FROM samples
       WHERE search_vector @@ to_tsquery('english', $1)
       ORDER BY rank DESC
       LIMIT $2 OFFSET $3`,
      [tsQuery, limit, offset],
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

  /** GET /api/samples/:tokenId - sample detail */
  fastify.get<{
    Params: { tokenId: string };
  }>('/api/samples/:tokenId', {
    schema: {
      params: {
        type: 'object',
        required: ['tokenId'],
        properties: {
          tokenId: { type: 'string', pattern: '^[0-9]+$' },
        },
      },
    },
  }, async (request, reply) => {
    const { tokenId } = request.params;

    const result = await query<Sample>(
      `SELECT s.*, c.display_name as creator_name, c.avatar_url as creator_avatar
       FROM samples s
       LEFT JOIN creators c ON s.creator_address = c.address
       WHERE s.token_id = $1`,
      [parseInt(tokenId, 10)],
    );

    if (result.rows.length === 0) {
      return reply.status(404).send({ error: 'Sample not found' });
    }

    return reply.send(result.rows[0]);
  });

  /** POST /api/samples/upload - initiate upload (authenticated, multipart) */
  fastify.post('/api/samples/upload', {
    preHandler: [fastify.authenticate],
    schema: {
      description: 'Upload a new audio sample',
    },
  }, async (request, reply) => {
    const creatorAddress = getAuthAddress(request);

    const data = await request.file();
    if (!data) {
      return reply.status(400).send({ error: 'No file provided' });
    }

    // Validate MIME type
    const allowedMimeTypes = [
      'audio/wav',
      'audio/x-wav',
      'audio/aiff',
      'audio/x-aiff',
      'audio/flac',
    ];
    if (!allowedMimeTypes.includes(data.mimetype)) {
      return reply.status(400).send({
        error: 'Invalid file type',
        message: `Allowed types: ${allowedMimeTypes.join(', ')}`,
      });
    }

    // Validate file size
    const maxBytes = config.maxUploadSizeMb * 1024 * 1024;
    const chunks: Buffer[] = [];
    let totalSize = 0;

    for await (const chunk of data.file) {
      totalSize += chunk.length;
      if (totalSize > maxBytes) {
        return reply.status(413).send({
          error: 'File too large',
          message: `Maximum file size is ${config.maxUploadSizeMb}MB`,
        });
      }
      chunks.push(chunk);
    }

    const fileBuffer = Buffer.concat(chunks);

    // Extract metadata from multipart fields
    const fields = data.fields;
    const title = (fields['title'] as { value?: string } | undefined)?.value;
    const description = (fields['description'] as { value?: string } | undefined)?.value;
    const sampleType = (fields['sample_type'] as { value?: string } | undefined)?.value;
    const licenseTier = (fields['license_tier'] as { value?: string } | undefined)?.value;
    const priceWei = (fields['price_wei'] as { value?: string } | undefined)?.value;
    const genre = (fields['genre'] as { value?: string } | undefined)?.value;
    const instrumentType = (fields['instrument_type'] as { value?: string } | undefined)?.value;
    const bpmStr = (fields['bpm'] as { value?: string } | undefined)?.value;
    const musicalKey = (fields['musical_key'] as { value?: string } | undefined)?.value;
    const editionLimitStr = (fields['edition_limit'] as { value?: string } | undefined)?.value;

    if (!title || !sampleType || !licenseTier || !priceWei) {
      return reply.status(400).send({
        error: 'Missing required fields',
        message: 'title, sample_type, license_tier, and price_wei are required',
      });
    }

    // Queue the transcode job
    const { transcodeQueue } = await import('../jobs/transcode.js');
    const job = await transcodeQueue.add('transcode', {
      fileData: fileBuffer.toString('base64'),
      originalName: data.filename,
      mimeType: data.mimetype,
      creatorAddress,
      title,
      description,
      bpm: bpmStr ? parseInt(bpmStr, 10) : undefined,
      musicalKey,
      sampleType,
      licenseTier,
      priceWei,
      editionLimit: editionLimitStr ? parseInt(editionLimitStr, 10) : undefined,
      genre,
      instrumentType,
    });

    return reply.status(202).send({
      message: 'Upload accepted and queued for processing',
      jobId: job.id,
    });
  });
}
