import type { FastifyBaseLogger } from "fastify";
import { prisma } from "../../lib/db.js";
import { pushStub } from "../push.js";

/**
 * A request is paid once a payment made for it reaches EXECUTED (the bank has sent the money; nothing after that can
 * fail it). Called by the state machine for every transition that leaves a payment EXECUTED or SETTLED, including
 * duplicates, so a webhook retried after a crash between the two writes still settles the request. Idempotent.
 * A request declined or expired while its payment was in flight is still marked paid: the money moved.
 */
export async function settleRequestForPayment(paymentId: string, log: FastifyBaseLogger, at: Date = new Date()): Promise<boolean> {
  const payment = await prisma.payment.findUnique({ where: { id: paymentId }, select: { requestId: true } });
  if (!payment?.requestId) return false;
  const result = await prisma.paymentRequest.updateMany({
    where: { id: payment.requestId, status: { not: "PAID" } },
    data: { status: "PAID", paymentId, paidAt: at },
  });
  if (result.count === 0) return false;
  const request = await prisma.paymentRequest.findUnique({ where: { id: payment.requestId }, select: { requesterUserId: true } });
  log.info({ requestId: payment.requestId, paymentId }, "payment request paid");
  pushStub(log, "request_paid", [request?.requesterUserId], { requestId: payment.requestId, paymentId });
  return true;
}

/**
 * Safety net for the one path a retried webhook cannot cover: a payment the fallback poll moved to EXECUTED whose
 * request write was lost (crash, locked database). The poll never looks at that payment again, so every tick settles
 * requests whose payment left the bank in the last day but which are not PAID yet. Normally finds nothing.
 */
export async function settleMissedRequests(log: FastifyBaseLogger, now: Date = new Date()): Promise<number> {
  const since = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const sent = await prisma.payment.findMany({
    where: { requestId: { not: null }, status: { in: ["EXECUTED", "SETTLED"] }, updatedAt: { gte: since } },
    select: { id: true, requestId: true },
    take: 500,
  });
  if (sent.length === 0) return 0;
  const open = await prisma.paymentRequest.findMany({
    where: { id: { in: sent.map((payment) => payment.requestId as string) }, status: { not: "PAID" } },
    select: { id: true },
  });
  const openIds = new Set(open.map((request) => request.id));
  let settled = 0;
  for (const payment of sent) {
    if (payment.requestId && openIds.has(payment.requestId) && (await settleRequestForPayment(payment.id, log, now))) {
      openIds.delete(payment.requestId);
      settled += 1;
    }
  }
  if (settled > 0) log.warn({ settled }, "settled requests whose payment had already executed");
  return settled;
}
