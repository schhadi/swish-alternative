import type { FastifyInstance } from "fastify";
import { currentUser, requireAuth } from "../lib/auth.js";

/**
 * Endpoints the app's tabs already call. They return empty lists until Phase 4 (collect) gives them real behaviour,
 * so a signed-in user sees the proper empty states instead of errors.
 */
export async function placeholderRoutes(app: FastifyInstance): Promise<void> {
  app.get("/orgs", { preHandler: requireAuth }, async (request) => {
    currentUser(request);
    return { organisations: [] };
  });
}
