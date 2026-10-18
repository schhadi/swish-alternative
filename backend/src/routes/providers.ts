import type { FastifyInstance } from "fastify";
import { requireAuth } from "../lib/auth.js";

export async function providerRoutes(app: FastifyInstance): Promise<void> {
  /** Banks the user can pick when linking an account. Phase 1: static GB list; Phase 2: TrueLayer, cached 1h. */
  app.get("/providers", { preHandler: requireAuth }, async () => {
    const providers = await app.services.providerSource.list();
    return { providers };
  });
}
