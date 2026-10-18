import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { currentUser, requireAuth } from "../lib/auth.js";

/**
 * Endpoints the app's tabs already call. They return empty lists until Phase 3 (requests) and Phase 4 (collect)
 * give them real behaviour, so a signed-in user sees the proper empty states instead of errors.
 */
export async function placeholderRoutes(app: FastifyInstance): Promise<void> {
  app.get("/requests", { preHandler: requireAuth }, async (request) => {
    currentUser(request);
    z.object({ role: z.enum(["incoming", "outgoing"]).default("incoming") }).parse(request.query);
    return { requests: [] };
  });

  app.get("/orgs", { preHandler: requireAuth }, async (request) => {
    currentUser(request);
    return { organisations: [] };
  });
}
