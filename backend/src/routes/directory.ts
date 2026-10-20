import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { currentUser, requireAuth } from "../lib/auth.js";
import { prisma } from "../lib/db.js";
import { initials } from "../lib/dto.js";
import { serverPhoneHash } from "../lib/phoneHash.js";
import { LIMITS } from "../limits.js";
import { coolingOffUntil } from "../services/bankAccounts.js";
import { providerDisplayName } from "../services/providers.js";

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
      const providers = await app.services.providerSource.list();
      const users = await prisma.user.findMany({
        // A number that verified a code but never set a name has not finished onboarding and is not "on Quid" yet.
        where: { phoneHash: { in: [...byServerHash.keys()] }, deletedAt: null, displayName: { not: "" }, NOT: { id: callerId } },
        select: {
          id: true,
          displayName: true,
          phoneHash: true,
          bankAccount: { select: { providerId: true, copStatus: true, createdAt: true, changedAt: true } },
        },
      });
      const now = Date.now();
      const registered = users.flatMap((user) => {
        const clientHash = user.phoneHash ? byServerHash.get(user.phoneHash) : undefined;
        if (!clientHash) return [];
        // What the picker needs to say whether this person can be paid right now: a bank name, never identifiers.
        const account = user.bankAccount;
        const coolingOff = account ? coolingOffUntil(account, now) : null;
        return [
          {
            hash: clientHash,
            userId: user.id,
            displayName: user.displayName,
            firstInitials: initials(user.displayName),
            bankName: account ? providerDisplayName(account.providerId, providers) ?? "Their bank" : null,
            canReceive: account?.copStatus === "MATCH" && coolingOff === null,
            coolingOffUntil: coolingOff?.toISOString() ?? null,
          },
        ];
      });
      return { registered };
    },
  );
}
