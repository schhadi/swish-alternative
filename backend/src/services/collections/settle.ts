import { Prisma } from "@prisma/client";
import type { FastifyBaseLogger } from "fastify";
import { prisma } from "../../lib/db.js";
import { withKeyedLock } from "../../lib/keyedLock.js";
import { pushStub } from "../push.js";

/** "Priya  PATEL " and "priya patel" are the same person on a collection list. */
export function nameKey(name: string): string {
  return name.trim().replace(/\s+/g, " ").toLowerCase();
}

/**
 * A collection payment counts once the bank has sent the money (EXECUTED). An in-app payer's member row was chosen
 * when the payment started; someone paying from the public link is matched at this point to an unpaid member with
 * the same name, or added as a new member, so abandoned link payments never leave rows behind (docs/DECISIONS.md
 * #83). Called from the state machine for every transition that leaves a payment EXECUTED or SETTLED; idempotent.
 */
export async function settleCollectionPayment(paymentId: string, log: FastifyBaseLogger, at: Date = new Date()): Promise<boolean> {
  const payment = await prisma.payment.findUnique({
    where: { id: paymentId },
    select: { collectionId: true, collectionMemberId: true, payerDisplayName: true, payerUserId: true },
  });
  if (!payment?.collectionId) return false;
  const collectionId = payment.collectionId;

  const settled = await withKeyedLock(`collection:${collectionId}`, async () => {
    if (await prisma.collectionMember.findUnique({ where: { paymentId }, select: { id: true } })) return null;
    if (payment.collectionMemberId) {
      const result = await prisma.collectionMember.updateMany({
        where: { id: payment.collectionMemberId, status: "UNPAID" },
        data: { status: "PAID", paymentId, paidAt: at },
      });
      return result.count === 1 ? payment.collectionMemberId : null;
    }
    const displayName = payment.payerDisplayName?.trim() || "Someone";
    const unpaid = await prisma.collectionMember.findMany({
      where: { collectionId, status: "UNPAID" },
      orderBy: { createdAt: "asc" },
      select: { id: true, displayName: true },
    });
    const match = unpaid.find((member) => nameKey(member.displayName) === nameKey(displayName));
    if (match) {
      const result = await prisma.collectionMember.updateMany({
        where: { id: match.id, status: "UNPAID" },
        data: { status: "PAID", paymentId, paidAt: at },
      });
      if (result.count === 1) return match.id;
    }
    try {
      const created = await prisma.collectionMember.create({
        data: { collectionId, userId: null, displayName, status: "PAID", paymentId, paidAt: at, createdAt: at },
      });
      return created.id;
    } catch (error) {
      // Another settlement of the same payment won the unique(paymentId) race.
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") return null;
      throw error;
    }
  });
  if (!settled) return false;
  const collection = await prisma.collection.findUnique({ where: { id: collectionId }, select: { org: { select: { createdByUserId: true } } } });
  log.info({ collectionId, memberId: settled, paymentId }, "collection member paid");
  pushStub(log, "collection_paid", [collection?.org.createdByUserId, payment.payerUserId], { collectionId, paymentId });
  return true;
}

/**
 * Safety net for a collection payment the fallback poll moved to EXECUTED whose member write was lost: every poll
 * tick settles payments that left the bank in the last day and that no member points to yet. Normally finds nothing.
 */
export async function settleMissedCollectionPayments(log: FastifyBaseLogger, now: Date = new Date()): Promise<number> {
  const since = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const sent = await prisma.payment.findMany({
    where: { collectionId: { not: null }, status: { in: ["EXECUTED", "SETTLED"] }, updatedAt: { gte: since } },
    select: { id: true },
    take: 500,
  });
  if (sent.length === 0) return 0;
  const recorded = await prisma.collectionMember.findMany({ where: { paymentId: { in: sent.map((payment) => payment.id) } }, select: { paymentId: true } });
  const done = new Set(recorded.map((member) => member.paymentId));
  let settled = 0;
  for (const payment of sent) {
    if (!done.has(payment.id) && (await settleCollectionPayment(payment.id, log, now))) settled += 1;
  }
  if (settled > 0) log.warn({ settled }, "settled collection payments that had already executed");
  return settled;
}
