import type { FastifyBaseLogger } from "fastify";
import { prisma } from "../../lib/db.js";
import { LIMITS } from "../../limits.js";
import { toPaymentStatus, type PaymentProvider } from "./provider.js";
import { applyTransition, type TransitionSource } from "./stateMachine.js";

/**
 * Fallback for payments whose webhook never arrived (docs/SPEC.md section 3): anything still in flight two minutes
 * after its last change is asked about directly. Webhooks remain the source of truth; the poll only catches up.
 */
export async function pollInFlightPayments(provider: PaymentProvider, log: FastifyBaseLogger, now: Date = new Date()): Promise<{ checked: number; changed: number }> {
  const stuckSince = new Date(now.getTime() - LIMITS.authorizingPollAfterMinutes * 60_000);
  const polledBefore = new Date(now.getTime() - LIMITS.pollIntervalSeconds * 1000);
  const candidates = await prisma.payment.findMany({
    where: {
      tlPaymentId: { not: null },
      status: { in: ["CREATED", "AUTHORIZING", "AUTHORIZED"] },
      updatedAt: { lt: stuckSince },
      OR: [{ lastPolledAt: null }, { lastPolledAt: { lt: polledBefore } }],
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
  return { checked: candidates.length, changed };
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
  await prisma.payment.updateMany({
    where: { id: paymentId },
    data: { lastPolledAt: now, providerStatus: state.status, ...(state.providerId ? { providerId: state.providerId } : {}) },
  });
  const mapped = toPaymentStatus(state);
  const outcome = await applyTransition(paymentId, { to: mapped.status, source, failureReason: mapped.failureReason, providerStatus: state.status, at: now }, log);
  return outcome.applied;
}
