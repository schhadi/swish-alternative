import type { PrismaClient } from "@prisma/client";
import { HttpError } from "../../lib/errors.js";
import { ukDateTime } from "../../lib/time.js";
import { LIMITS } from "../../limits.js";
import { coolingOffUntil } from "../bankAccounts.js";

/** Risk rules for POST /payments (docs/SPEC.md section 7). Everything here runs under the payer's creation lock. */

type Tx = Pick<PrismaClient, "payment" | "user" | "bankAccount">;

const DAY_MS = 24 * 60 * 60 * 1000;

export function pounds(minor: number): string {
  return `£${(minor / 100).toFixed(minor % 100 === 0 ? 0 : 2)}`;
}

/** Sent (or in flight) by this payer since `since`. In-flight payments count, so parallel requests cannot bypass a window. */
async function sentSince(tx: Tx, payerUserId: string, since: Date): Promise<number> {
  const aggregate = await tx.payment.aggregate({
    _sum: { amountMinor: true },
    where: { payerUserId, createdAt: { gte: since }, status: { notIn: ["FAILED", "CANCELLED"] } },
  });
  return aggregate._sum.amountMinor ?? 0;
}

export async function assertWithinLimits(tx: Tx, payerUserId: string, amountMinor: number, now: Date): Promise<void> {
  if (amountMinor > LIMITS.perPaymentMinor) {
    throw new HttpError(400, "limit_per_payment", `The most you can send in one payment is ${pounds(LIMITS.perPaymentMinor)}.`, {
      limitMinor: LIMITS.perPaymentMinor,
      remainingMinor: LIMITS.perPaymentMinor,
    });
  }
  const day = await sentSince(tx, payerUserId, new Date(now.getTime() - DAY_MS));
  if (day + amountMinor > LIMITS.rolling24hMinor) {
    const remaining = Math.max(0, LIMITS.rolling24hMinor - day);
    throw new HttpError(400, "limit_24h", `You can send ${pounds(remaining)} more in the next 24 hours.`, {
      limitMinor: LIMITS.rolling24hMinor,
      remainingMinor: remaining,
    });
  }
  const month = await sentSince(tx, payerUserId, new Date(now.getTime() - 30 * DAY_MS));
  if (month + amountMinor > LIMITS.rolling30dMinor) {
    const remaining = Math.max(0, LIMITS.rolling30dMinor - month);
    throw new HttpError(400, "limit_30d", `You can send ${pounds(remaining)} more in the next 30 days.`, {
      limitMinor: LIMITS.rolling30dMinor,
      remainingMinor: remaining,
    });
  }
}

export interface PayableUser {
  id: string;
  displayName: string;
  bankAccount: {
    sortCodeEnc: string;
    accountNumberEnc: string;
    accountHolderNameEnc: string;
    providerId: string | null;
    copStatus: string;
    createdAt: Date;
    changedAt: Date;
  };
}

/** The payee must be a live, named user with a verified bank account that is not in its cooling-off window. */
export async function loadPayableUser(tx: Tx, payeeUserId: string, payerUserId: string, now: Date): Promise<PayableUser> {
  if (payeeUserId === payerUserId) {
    throw new HttpError(400, "self_payment", "You can't pay yourself.");
  }
  const payee = await tx.user.findUnique({ where: { id: payeeUserId }, include: { bankAccount: true } });
  if (!payee || payee.deletedAt || payee.displayName === "") {
    throw new HttpError(404, "payee_not_found", "We couldn't find that person on Quid.");
  }
  if (!payee.bankAccount || payee.bankAccount.copStatus !== "MATCH") {
    throw new HttpError(400, "payee_not_payable", `${payee.displayName} hasn't linked a verified bank account yet, so they can't be paid.`);
  }
  const until = coolingOffUntil(payee.bankAccount, now.getTime());
  if (until) {
    throw new HttpError(400, "payee_cooling_off", `${payee.displayName} changed their bank account recently and can receive payments again from ${ukDateTime(until)}.`, {
      coolingOffUntil: until.toISOString(),
    });
  }
  return { id: payee.id, displayName: payee.displayName, bankAccount: payee.bankAccount };
}

/** Faster Payments references: letters, digits, space and & . / - only, at most 18 characters after tidying. */
const REFERENCE_PATTERN = /^[A-Za-z0-9 &./-]+$/;

export function normaliseReference(raw: string): string {
  const tidy = raw.trim().replace(/\s+/g, " ");
  if (tidy.length === 0 || tidy.length > LIMITS.referenceMaxLength || !REFERENCE_PATTERN.test(tidy)) {
    throw new HttpError(400, "invalid_reference", `Use up to ${LIMITS.referenceMaxLength} letters, numbers, spaces or & . / -`);
  }
  return tidy;
}

/** "First time paying this person" (docs/SPEC.md section 7): no completed payment from payer to payee yet. */
export async function isFirstTimePayee(tx: Tx, payerUserId: string, payeeUserId: string): Promise<boolean> {
  const completed = await tx.payment.count({ where: { payerUserId, payeeUserId, status: { in: ["EXECUTED", "SETTLED"] } } });
  return completed === 0;
}

/**
 * Starting to pay someone new discloses their bank-held name for the warning sheet, so a payer can start at most
 * LIMITS.newPayeesPer24h new people a day. A second attempt to the same person the same day costs nothing more.
 */
export async function assertNewPayeeAllowance(tx: Tx, payerUserId: string, payeeUserId: string, now: Date): Promise<void> {
  const since = new Date(now.getTime() - DAY_MS);
  const disclosed = await tx.payment.findMany({
    where: { payerUserId, firstTimePayee: true, payeeUserId: { not: null }, createdAt: { gte: since } },
    select: { payeeUserId: true },
    distinct: ["payeeUserId"],
  });
  if (disclosed.some((row) => row.payeeUserId === payeeUserId)) return;
  if (disclosed.length >= LIMITS.newPayeesPer24h) {
    throw new HttpError(
      429,
      "new_payee_limit",
      `You can start paying up to ${LIMITS.newPayeesPer24h} new people a day. You can still pay people you've paid before.`,
      { limit: LIMITS.newPayeesPer24h },
    );
  }
}
