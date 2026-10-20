import type { FastifyBaseLogger } from "fastify";
import { prisma } from "../../lib/db.js";
import { LIMITS } from "../../limits.js";
import { toPaymentStatus, type PaymentProvider } from "./provider.js";
import { applyTransition, type TransitionSource } from "./stateMachine.js";

/**
 * Fallback for payments whose webhook never arrived (docs/SPEC.md section 3): anything still in flight is first asked
 * about two minutes after its last change, then once per poll interval until it is terminal. Webhooks remain the
 * source of truth; the poll only catches up.
 */
export async function pollInFlightPayments(provider: PaymentProvider, log: FastifyBaseLogger, now: Date = new Date()): Promise<{ checked: number; changed: number; abandoned: number }> {
  const abandoned = await failAbandonedCreations(log, now);
  const stuckSince = new Date(now.getTime() - LIMITS.authorizingPollAfterMinutes * 60_000);
  const polledBefore = new Date(now.getTime() - LIMITS.pollIntervalSeconds * 1000);
  const candidates = await prisma.payment.findMany({
    where: {
      tlPaymentId: { not: null },
      status: { in: ["CREATED", "AUTHORIZING", "AUTHORIZED"] },
      // The poll's own bookkeeping bumps updatedAt, so only the first poll waits on the quiet period.
      OR: [{ lastPolledAt: null, updatedAt: { lt: stuckSince } }, { lastPolledAt: { lt: polledBefore } }],
    },
    select: { id: true, tlPaymentId: true },
    take: 100,
  });
  let changed = 0;
  for (const candidate of candidates) {
    if (!candidate.tlPaymentId) continue;
    const outcome = await reconcilePayment(candidate.id, candidate.tlPaymentId, provider, "poll", log, now);
    if (outcome) changed += 1;
  }
  return { checked: candidates.length, changed, abandoned };
}

/**
 * A CREATED row with no provider payment means the process died between the insert and the provider's answer.
 * Nobody holds a token for it, so after ten minutes it is failed and stops counting against the payer's allowance.
 */
async function failAbandonedCreations(log: FastifyBaseLogger, now: Date): Promise<number> {
  const before = new Date(now.getTime() - LIMITS.createdWithoutProviderExpiryMinutes * 60_000);
  const orphans = await prisma.payment.findMany({
    where: { status: "CREATED", tlPaymentId: null, createdAt: { lt: before } },
    select: { id: true },
    take: 100,
  });
  let failed = 0;
  for (const orphan of orphans) {
    const outcome = await applyTransition(orphan.id, { to: "FAILED", source: "poll", failureReason: "abandoned", at: now }, log);
    if (outcome.applied) failed += 1;
  }
  return failed;
}

/** Asks the provider for one payment and applies what it says. Returns true when the status changed. */
export async function reconcilePayment(paymentId: string, providerPaymentId: string, provider: PaymentProvider, source: TransitionSource, log: FastifyBaseLogger, now: Date = new Date()): Promise<boolean> {
  let state;
  try {
    state = await provider.getPayment(providerPaymentId);
  } catch (error) {
    log.warn({ paymentId, err: error }, "payment poll failed");
    await prisma.payment.updateMany({ where: { id: paymentId }, data: { lastPolledAt: now } });
    return false;
  }
  // providerStatus is written by the transition together with the status it belongs to, never from a stale read.
  await prisma.payment.updateMany({
    where: { id: paymentId },
    data: { lastPolledAt: now, ...(state.providerId ? { providerId: state.providerId } : {}) },
  });
  const mapped = toPaymentStatus(state);
  const outcome = await applyTransition(paymentId, { to: mapped.status, source, failureReason: mapped.failureReason, providerStatus: state.status, at: now }, log);
  return outcome.applied;
}
