import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { currentUser, requireAuth } from "../lib/auth.js";
import { prisma } from "../lib/db.js";
import { paymentDTO } from "../lib/dto.js";
import { HttpError } from "../lib/errors.js";
import { LIMITS } from "../limits.js";
import { createPeerPayment } from "../services/payments/create.js";
import { providerDisplayName } from "../services/providers.js";

const FeedQuery = z.object({
  role: z.enum(["sent", "received"]),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

const CreateBody = z.object({
  payeeUserId: z.string().min(1).optional(),
  collectionId: z.string().min(1).optional(),
  requestId: z.string().min(1).optional(),
  amountMinor: z.number().int().positive(),
  reference: z.string().min(1).max(64),
});

const include = {
  payer: { select: { id: true, displayName: true } },
  payee: { select: { id: true, displayName: true } },
  collection: { select: { org: { select: { name: true } } } },
} as const;

export async function paymentRoutes(app: FastifyInstance): Promise<void> {
  const creationLimit = app.rateLimit({
    max: LIMITS.paymentCreationsPerMinute,
    timeWindow: "1 minute",
    keyGenerator: (request: FastifyRequest) => request.user?.id ?? request.ip,
  });

  /**
   * Starts a payment (docs/SPEC.md section 5): checks the rules, creates it with the provider and hands the app
   * what it needs to authorise in the payer's bank. The payee's account-holder name is returned here and nowhere
   * else, for the first-time-payee warning (section 7).
   */
  app.post("/payments", { preHandler: [requireAuth, creationLimit] }, async (request, reply) => {
    const user = currentUser(request);
    const body = CreateBody.parse(request.body);
    if (body.collectionId || body.requestId) {
      throw new HttpError(400, "not_supported_yet", "Paying a request or a collection arrives in a later phase.");
    }
    if (!body.payeeUserId) {
      throw new HttpError(400, "validation_error", "Choose who to pay.");
    }
    const created = await createPeerPayment(
      app.services.paymentProvider,
      { payer: user, payeeUserId: body.payeeUserId, amountMinor: body.amountMinor, reference: body.reference },
      request.log,
    );
    const providers = await app.services.providerSource.list();
    const payment = await prisma.payment.findUniqueOrThrow({ where: { id: created.payment.id }, include });
    return reply.status(201).send({
      paymentId: created.payment.id,
      tlPaymentId: created.payment.tlPaymentId,
      resourceToken: created.resourceToken,
      authorisationUrl: created.authorisationUrl,
      firstTimePayee: created.firstTimePayee,
      payee: {
        userId: created.payee.userId,
        displayName: created.payee.displayName,
        accountHolderName: created.payee.accountHolderName,
        copStatus: created.payee.copStatus,
        bankName: providerDisplayName(created.payee.providerId, providers) ?? "Their bank",
      },
      payment: paymentDTO(payment, user.id, providers),
    });
  });

  /** Activity feed, newest first. */
  app.get("/payments", { preHandler: requireAuth }, async (request) => {
    const { id } = currentUser(request);
    const { role, limit } = FeedQuery.parse(request.query);
    const providers = await app.services.providerSource.list();
    const rows = await prisma.payment.findMany({
      where: role === "sent" ? { payerUserId: id } : { payeeUserId: id },
      orderBy: { createdAt: "desc" },
      take: limit,
      include,
    });
    return { payments: rows.map((row) => paymentDTO(row, id, providers)) };
  });

  app.get("/payments/:id", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const { id } = z.object({ id: z.string().min(1) }).parse(request.params);
    const providers = await app.services.providerSource.list();
    const row = await prisma.payment.findFirst({
      where: { id, OR: [{ payerUserId: userId }, { payeeUserId: userId }] },
      include,
    });
    if (!row) {
      throw new HttpError(404, "not_found", "We couldn't find that payment.");
    }
    return paymentDTO(row, userId, providers);
  });
}
