import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { currentUser, requireAuth } from "../lib/auth.js";
import { prisma } from "../lib/db.js";
import { paymentDTO } from "../lib/dto.js";
import { HttpError } from "../lib/errors.js";

const FeedQuery = z.object({
  role: z.enum(["sent", "received"]),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

const include = {
  payer: { select: { id: true, displayName: true } },
  payee: { select: { id: true, displayName: true } },
  collection: { select: { org: { select: { name: true } } } },
} as const;

export async function paymentRoutes(app: FastifyInstance): Promise<void> {
  /** Activity feed. Empty until Phase 2 creates payments; the shape is final. */
  app.get("/payments", { preHandler: requireAuth }, async (request) => {
    const { id } = currentUser(request);
    const { role, limit } = FeedQuery.parse(request.query);
    const rows = await prisma.payment.findMany({
      where: role === "sent" ? { payerUserId: id } : { payeeUserId: id },
      orderBy: { createdAt: "desc" },
      take: limit,
      include,
    });
    return { payments: rows.map((row) => paymentDTO(row, id)) };
  });

  app.get("/payments/:id", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const { id } = z.object({ id: z.string().min(1) }).parse(request.params);
    const row = await prisma.payment.findFirst({
      where: { id, OR: [{ payerUserId: userId }, { payeeUserId: userId }] },
      include,
    });
    if (!row) {
      throw new HttpError(404, "not_found", "We couldn't find that payment.");
    }
    return paymentDTO(row, userId);
  });
}
