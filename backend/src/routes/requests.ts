import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { currentUser, requireAuth } from "../lib/auth.js";
import { prisma } from "../lib/db.js";
import { requestDTO, splitDTO } from "../lib/dto.js";
import { HttpError } from "../lib/errors.js";
import { LIMITS } from "../limits.js";
import {
  createRequest,
  createSplit,
  declineRequest,
  remindRequest,
  remindSplit,
  requestInclude,
  splitInclude,
} from "../services/requests/service.js";

const ListQuery = z.object({
  role: z.enum(["incoming", "outgoing"]).default("incoming"),
  status: z.enum(["pending", "all"]).default("all"),
  /** Only the requests in this split: how a split link finds the viewer's own share however old it is. */
  splitId: z.string().min(1).max(64).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

const IdParams = z.object({ id: z.string().min(1).max(64) });

const CreateRequestBody = z.object({
  payerUserId: z.string().min(1).max(64),
  amountMinor: z.number().int(),
  reference: z.string().min(1).max(64),
  note: z.string().max(500).nullish(),
});

const CreateSplitBody = z.object({
  title: z.string().max(200),
  totalMinor: z.number().int(),
  shares: z
    .array(z.object({ userId: z.string().min(1).max(64), amountMinor: z.number().int() }))
    .max(LIMITS.splitMaxShares * 2),
});

const RemindSplitBody = z.object({ requestIds: z.array(z.string().min(1).max(64)).max(LIMITS.splitMaxShares).optional() }).default({});

/** Requests and splits (docs/SPEC.md section 5, Phase 3). */
export async function requestRoutes(app: FastifyInstance): Promise<void> {
  const perUser = (request: FastifyRequest) => request.user?.id ?? request.ip;
  // One budget for POST /requests and POST /splits, one for every reminder call.
  const creationLimit = app.rateLimit({ max: LIMITS.requestCreationsPerMinute, timeWindow: "1 minute", keyGenerator: perUser });
  const reminderLimit = app.rateLimit({ max: LIMITS.reminderCallsPerMinute, timeWindow: "1 minute", keyGenerator: perUser });

  async function loadRequest(id: string) {
    return prisma.paymentRequest.findUnique({ where: { id }, include: requestInclude });
  }

  /** incoming = addressed to me (Home shows the pending ones); outgoing = mine to others. Newest first. */
  app.get("/requests", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const { role, status, splitId, limit } = ListQuery.parse(request.query);
    const now = new Date();
    const rows = await prisma.paymentRequest.findMany({
      where: {
        ...(role === "incoming" ? { payerUserId: userId } : { requesterUserId: userId }),
        ...(status === "pending" ? { status: "PENDING", expiresAt: { gt: now } } : {}),
        ...(splitId ? { splitShare: { splitId } } : {}),
      },
      orderBy: { createdAt: "desc" },
      take: limit,
      include: requestInclude,
    });
    return { requests: rows.map((row) => requestDTO(row, now)) };
  });

  app.get("/requests/:id", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const { id } = IdParams.parse(request.params);
    const row = await loadRequest(id);
    if (!row || (row.requesterUserId !== userId && row.payerUserId !== userId)) {
      throw new HttpError(404, "request_not_found", "We couldn't find that request.");
    }
    return requestDTO(row);
  });

  app.post("/requests", { preHandler: [requireAuth, creationLimit] }, async (request, reply) => {
    const user = currentUser(request);
    const body = CreateRequestBody.parse(request.body);
    const row = await createRequest({ requesterUserId: user.id, payerUserId: body.payerUserId, amountMinor: body.amountMinor, reference: body.reference, note: body.note }, request.log);
    return reply.status(201).send(requestDTO(row));
  });

  app.post("/requests/:id/decline", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const { id } = IdParams.parse(request.params);
    await declineRequest(id, userId, request.log);
    return requestDTO((await loadRequest(id))!);
  });

  app.post("/requests/:id/remind", { preHandler: [requireAuth, reminderLimit] }, async (request) => {
    const { id: userId } = currentUser(request);
    const { id } = IdParams.parse(request.params);
    await remindRequest(id, userId, request.log);
    return requestDTO((await loadRequest(id))!);
  });

  app.post("/splits", { preHandler: [requireAuth, creationLimit] }, async (request, reply) => {
    const user = currentUser(request);
    const body = CreateSplitBody.parse(request.body);
    const splitId = await createSplit({ creatorUserId: user.id, title: body.title, totalMinor: body.totalMinor, shares: body.shares }, request.log);
    const split = await prisma.split.findUniqueOrThrow({ where: { id: splitId }, include: splitInclude });
    return reply.status(201).send(splitDTO(split));
  });

  /** The creator's splits, newest first (the app's Requests list). */
  app.get("/splits", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const { limit } = z.object({ limit: z.coerce.number().int().min(1).max(100).default(50) }).parse(request.query);
    const now = new Date();
    const rows = await prisma.split.findMany({ where: { creatorUserId: userId }, orderBy: { createdAt: "desc" }, take: limit, include: splitInclude });
    return { splits: rows.map((row) => splitDTO(row, now)) };
  });

  /** Creator only. Someone asked in the split sees their own request instead (GET /requests). */
  app.get("/splits/:id", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const { id } = IdParams.parse(request.params);
    const split = await prisma.split.findUnique({ where: { id }, include: splitInclude });
    if (!split || split.creatorUserId !== userId) {
      throw new HttpError(404, "split_not_found", "We couldn't find that split.");
    }
    return splitDTO(split);
  });

  app.post("/splits/:id/remind", { preHandler: [requireAuth, reminderLimit] }, async (request) => {
    const { id: userId } = currentUser(request);
    const { id } = IdParams.parse(request.params);
    const { requestIds } = RemindSplitBody.parse(request.body ?? {});
    const outcome = await remindSplit(id, userId, requestIds, request.log);
    const split = await prisma.split.findUniqueOrThrow({ where: { id }, include: splitInclude });
    return { ...outcome, split: splitDTO(split) };
  });
}
