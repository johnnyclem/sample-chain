import type { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import type { JwtPayload } from '../types.js';

/**
 * Register JWT verification decorator on the Fastify instance.
 * After registration, routes can use `{ preHandler: [fastify.authenticate] }`.
 */
export async function registerAuthMiddleware(fastify: FastifyInstance): Promise<void> {
  fastify.decorate(
    'authenticate',
    async function (request: FastifyRequest, reply: FastifyReply): Promise<void> {
      try {
        await request.jwtVerify();
      } catch {
        reply.status(401).send({ error: 'Unauthorized', message: 'Invalid or missing authentication token' });
      }
    },
  );
}

/** Helper to extract the authenticated address from the JWT payload */
export function getAuthAddress(request: FastifyRequest): string {
  const payload = request.user as JwtPayload;
  return payload.address;
}
