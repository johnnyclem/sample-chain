import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import multipart from '@fastify/multipart';
import rateLimit from '@fastify/rate-limit';
import swagger from '@fastify/swagger';

import { config } from './config.js';
import { registerAuthMiddleware } from './middleware/auth.js';
import { registerAuthRoutes } from './auth/siwe.js';
import { registerSampleRoutes } from './routes/samples.js';
import { registerCreatorRoutes } from './routes/creators.js';
import { registerMarketplaceRoutes } from './routes/marketplace.js';
import { registerWalletRoutes } from './routes/wallet.js';

// Augment Fastify types with our custom decorators
declare module 'fastify' {
  interface FastifyInstance {
    authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: { address: string };
    user: { address: string };
  }
}

async function buildApp() {
  const fastify = Fastify({
    logger: {
      level: config.nodeEnv === 'production' ? 'info' : 'debug',
    },
  });

  // Register CORS
  await fastify.register(cors, {
    origin: config.corsOrigin,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    credentials: true,
  });

  // Register JWT
  await fastify.register(jwt, {
    secret: config.jwtSecret,
  });

  // Register multipart (file uploads)
  await fastify.register(multipart, {
    limits: {
      fileSize: config.maxUploadSizeMb * 1024 * 1024,
      files: 1,
    },
  });

  // Register rate limiting
  await fastify.register(rateLimit, {
    max: config.rateLimitMax,
    timeWindow: config.rateLimitWindowMs,
  });

  // Register Swagger documentation
  await fastify.register(swagger, {
    openapi: {
      info: {
        title: 'SampleChain API',
        description: 'Backend API for the SampleChain music sample marketplace',
        version: '1.0.0',
      },
      servers: [
        { url: `http://localhost:${config.port}`, description: 'Development server' },
      ],
    },
  });

  // Register auth middleware (decorates fastify.authenticate)
  await registerAuthMiddleware(fastify);

  // Register routes
  await registerAuthRoutes(fastify);
  await registerSampleRoutes(fastify);
  await registerCreatorRoutes(fastify);
  await registerMarketplaceRoutes(fastify);
  await registerWalletRoutes(fastify);

  // Health check
  fastify.get('/health', async () => {
    return { status: 'ok', timestamp: new Date().toISOString() };
  });

  return fastify;
}

async function start() {
  const app = await buildApp();

  try {
    await app.listen({ port: config.port, host: config.host });
    console.log(`SampleChain API server listening on ${config.host}:${config.port}`);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }

  // Graceful shutdown
  const signals: NodeJS.Signals[] = ['SIGINT', 'SIGTERM'];
  for (const signal of signals) {
    process.on(signal, async () => {
      console.log(`Received ${signal}, shutting down...`);
      await app.close();
      process.exit(0);
    });
  }
}

start();
