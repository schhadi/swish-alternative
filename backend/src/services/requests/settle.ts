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
