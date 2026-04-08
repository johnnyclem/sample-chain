import type { FastifyInstance } from 'fastify';
import { SiweMessage, generateNonce } from 'siwe';

/** In-memory nonce store. In production, use Redis or DB. */
const nonceStore = new Map<string, { nonce: string; expiresAt: number }>();

const NONCE_TTL_MS = 5 * 60 * 1000; // 5 minutes

function cleanExpiredNonces(): void {
  const now = Date.now();
  for (const [key, value] of nonceStore) {
    if (value.expiresAt < now) {
      nonceStore.delete(key);
    }
  }
}

export async function registerAuthRoutes(fastify: FastifyInstance): Promise<void> {
  /** Generate a nonce for SIWE authentication */
  fastify.post('/auth/nonce', async (_request, reply) => {
    cleanExpiredNonces();

    const nonce = generateNonce();
    const id = nonce; // use nonce itself as the key
    nonceStore.set(id, {
      nonce,
      expiresAt: Date.now() + NONCE_TTL_MS,
    });

    return reply.send({ nonce });
  });

  /** Verify a SIWE signature and return a JWT */
  fastify.post<{
    Body: { message: string; signature: string };
  }>('/auth/login', {
    schema: {
      body: {
        type: 'object',
        required: ['message', 'signature'],
        properties: {
          message: { type: 'string' },
          signature: { type: 'string' },
        },
      },
    },
  }, async (request, reply) => {
    const { message, signature } = request.body;

    try {
      const siweMessage = new SiweMessage(message);
      const result = await siweMessage.verify({ signature });

      if (!result.success) {
        return reply.status(401).send({ error: 'Invalid signature' });
      }

      const { nonce, address } = result.data;

      // Verify nonce exists and hasn't expired
      const stored = nonceStore.get(nonce);
      if (!stored || stored.expiresAt < Date.now()) {
        nonceStore.delete(nonce);
        return reply.status(401).send({ error: 'Invalid or expired nonce' });
      }

      // Consume nonce (one-time use)
      nonceStore.delete(nonce);

      // Issue JWT
      const token = fastify.jwt.sign(
        { address: address.toLowerCase() },
        { expiresIn: '24h' },
      );

      return reply.send({
        token,
        address: address.toLowerCase(),
      });
    } catch (err) {
      fastify.log.error(err, 'SIWE verification failed');
      return reply.status(401).send({ error: 'Authentication failed' });
    }
  });
}
