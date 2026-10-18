import type { FastifyInstance } from "fastify";
import { pingDatabase } from "../lib/db.js";
import { env } from "../config.js";

export const SERVICE_NAME = "quid-backend";
export const SERVICE_VERSION = "0.1.0";

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get("/health", async (_request, reply) => {
    const dbOk = await pingDatabase();
    const body = {
      status: dbOk ? "ok" : "degraded",
      service: SERVICE_NAME,
      version: SERVICE_VERSION,
      environment: env.NODE_ENV,
      db: dbOk ? "ok" : "error",
      time: new Date().toISOString(),
    };
    return reply.status(dbOk ? 200 : 503).send(body);
  });
}
