import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { currentUser, requireAuth } from "../lib/auth.js";
import { prisma } from "../lib/db.js";
import { initials } from "../lib/dto.js";
import { serverPhoneHash } from "../lib/phoneHash.js";
import { LIMITS } from "../limits.js";

const LookupBody = z.object({
  hashes: z
    .array(z.string().regex(/^[0-9a-f]{64}$/, "Each hash is 64 lowercase hex characters"))
    .min(1)
    .max(LIMITS.directoryLookupMaxHashes, `At most ${LIMITS.directoryLookupMaxHashes} hashes per request`),
});

export async function directoryRoutes(app: FastifyInstance): Promise<void> {
  /**
   * Which of these contacts are on Quid. The app sends SHA-256 client hashes (never numbers); the server peppers
   * them and matches User.phoneHash. Only registered hashes come back, never the caller's own entry.
   */
  // The limiter runs after requireAuth so it can key on the user, not the IP.
  const perUserLimit = app.rateLimit({
    max: LIMITS.directoryLookupRequestsPerMinute,
    timeWindow: "1 minute",
    keyGenerator: (request: FastifyRequest) => request.user?.id ?? request.ip,
  });

  app.post(
    "/directory/lookup",
    { preHandler: [requireAuth, perUserLimit] },
    async (request) => {
      const { id: callerId } = currentUser(request);
      const { hashes } = LookupBody.parse(request.body);
      const unique = [...new Set(hashes)];
      const byServerHash = new Map(unique.map((clientHash) => [serverPhoneHash(clientHash), clientHash]));
      const users = await prisma.user.findMany({
        where: { phoneHash: { in: [...byServerHash.keys()] }, deletedAt: null, NOT: { id: callerId } },
        select: { id: true, displayName: true, phoneHash: true },
      });
      const registered = users.flatMap((user) => {
        const clientHash = user.phoneHash ? byServerHash.get(user.phoneHash) : undefined;
        if (!clientHash) return [];
        return [{ hash: clientHash, userId: user.id, displayName: user.displayName, firstInitials: initials(user.displayName) }];
      });
      return { registered };
    },
  );
}
