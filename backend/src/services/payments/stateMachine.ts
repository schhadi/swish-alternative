import type { PaymentStatus } from "@prisma/client";
import type { FastifyBaseLogger } from "fastify";
import { prisma } from "../../lib/db.js";

/**
 * The payment state machine (docs/SPEC.md sections 3 and 7, docs/DECISIONS.md #60).
 * CREATED -> AUTHORIZING -> AUTHORIZED -> EXECUTED -> SETTLED, with FAILED and CANCELLED as the terminal failures.
 * Webhooks, the fallback poll and the create flow all go through applyTransition, which is the only place a
 * status changes and the only place a change is logged.
 */
export type TransitionSource = "webhook" | "poll" | "user";

export const RANK: Record<PaymentStatus, number> = {
  CREATED: 0,
  AUTHORIZING: 1,
  AUTHORIZED: 2,
  EXECUTED: 3,
  SETTLED: 4,
  FAILED: 5,
  CANCELLED: 5,
};

export const TERMINAL: ReadonlySet<PaymentStatus> = new Set(["SETTLED", "FAILED", "CANCELLED"]);
const FAILURE: ReadonlySet<PaymentStatus> = new Set(["FAILED", "CANCELLED"]);

/**
 * Why a transition was not applied. "stale" is the normal out-of-order case (an earlier stage reported after a later
 * one, settled before executed, say) and is logged quietly; "terminal" and "invalid" are real conflicts and warn.
 */
export function classifyIgnored(from: PaymentStatus, to: PaymentStatus): "stale" | "terminal" | "invalid" {
  if (!FAILURE.has(from) && RANK[to] < RANK[from]) return "stale";
  if (TERMINAL.has(from)) return "terminal";
  return "invalid";
}

export const ALLOWED_FROM: Record<PaymentStatus, readonly PaymentStatus[]> = {
  CREATED: [],
  AUTHORIZING: ["CREATED"],
  AUTHORIZED: ["CREATED", "AUTHORIZING"],
  // A settled or executed webhook can arrive before the authorized one; forward jumps are fine.
  EXECUTED: ["CREATED", "AUTHORIZING", "AUTHORIZED"],
  SETTLED: ["CREATED", "AUTHORIZING", "AUTHORIZED", "EXECUTED"],
  // Once the bank has executed, a payment cannot fail.
  FAILED: ["CREATED", "AUTHORIZING", "AUTHORIZED"],
  CANCELLED: ["CREATED", "AUTHORIZING"],
};

export interface TransitionInput {
  to: PaymentStatus;
  source: TransitionSource;
  failureReason?: string | null;
  providerStatus?: string | null;
  providerId?: string | null;
  at?: Date;
}

export type TransitionOutcome =
  | { applied: true; from: PaymentStatus; to: PaymentStatus }
  | { applied: false; reason: "duplicate" | "stale" | "terminal" | "invalid" | "missing" | "contended"; current: PaymentStatus | null };

export async function applyTransition(paymentId: string, input: TransitionInput, log: FastifyBaseLogger): Promise<TransitionOutcome> {
  const allowedFrom = ALLOWED_FROM[input.to];
  const at = input.at ?? new Date();
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const current = await prisma.payment.findUnique({ where: { id: paymentId }, select: { status: true } });
    if (!current) {
      log.warn({ paymentId, to: input.to, source: input.source }, "payment transition for unknown payment");
      return { applied: false, reason: "missing", current: null };
    }
    const from = current.status;
    if (from === input.to) {
      log.debug({ paymentId, status: from, source: input.source }, "payment transition duplicate");
      return { applied: false, reason: "duplicate", current: from };
    }
    if (!allowedFrom.includes(from)) {
      const reason = classifyIgnored(from, input.to);
      log[reason === "stale" ? "info" : "warn"]({ paymentId, from, to: input.to, source: input.source, reason }, "payment transition ignored");
      return { applied: false, reason, current: from };
    }
    const result = await prisma.payment.updateMany({
      where: { id: paymentId, status: from },
      data: {
        status: input.to,
        ...(input.to === "SETTLED" ? { settledAt: at } : {}),
        ...(input.failureReason !== undefined ? { failureReason: input.failureReason } : {}),
        ...(input.providerStatus !== undefined ? { providerStatus: input.providerStatus } : {}),
        ...(input.providerId ? { providerId: input.providerId } : {}),
      },
    });
    if (result.count === 1) {
      log.info({ paymentId, from, to: input.to, source: input.source }, "payment status changed");
      return { applied: true, from, to: input.to };
    }
    // Someone else changed the row between the read and the write: look again.
  }
  log.warn({ paymentId, to: input.to, source: input.source }, "payment transition contended");
  return { applied: false, reason: "contended", current: null };
}
