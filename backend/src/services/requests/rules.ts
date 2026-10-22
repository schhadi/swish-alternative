import type { PaymentRequest, RequestStatus } from "@prisma/client";
import { prisma } from "../../lib/db.js";
import { HttpError } from "../../lib/errors.js";
import { ukDateTime } from "../../lib/time.js";
import { LIMITS } from "../../limits.js";
import { coolingOffUntil } from "../bankAccounts.js";
import { pounds } from "../payments/rules.js";

/** Rules for requests and splits (docs/SPEC.md sections 5 and 7, docs/DECISIONS.md #72-#74). */

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/** A PENDING request past its expiry reads as EXPIRED, so answers are right between two sweeps. */
export function effectiveRequestStatus(row: Pick<PaymentRequest, "status" | "expiresAt">, now: Date = new Date()): RequestStatus {
  return row.status === "PENDING" && row.expiresAt.getTime() <= now.getTime() ? "EXPIRED" : row.status;
}

/** When the requester may nudge again; null means now. Reminders are once per 24h per request. */
export function nextReminderAt(row: Pick<PaymentRequest, "lastRemindedAt">): Date | null {
  return row.lastRemindedAt ? new Date(row.lastRemindedAt.getTime() + LIMITS.reminderMinIntervalHours * HOUR_MS) : null;
}

export function requestExpiry(now: Date): Date {
  return new Date(now.getTime() + LIMITS.requestExpiryDays * DAY_MS);
}

/** Asking for money only makes sense if people can pay you: a verified account outside its cooling-off window. */
export async function assertRequesterCanReceive(userId: string, now: Date): Promise<void> {
  const account = await prisma.bankAccount.findUnique({ where: { userId }, select: { copStatus: true, createdAt: true, changedAt: true } });
  if (!account || account.copStatus !== "MATCH") {
    throw new HttpError(400, "requester_not_payable", "Link a verified bank account first, so people can pay you.");
  }
  const until = coolingOffUntil(account, now.getTime());
  if (until) {
    throw new HttpError(400, "requester_cooling_off", `You changed your bank account recently. You can ask for money again from ${ukDateTime(until)}.`, {
      coolingOffUntil: until.toISOString(),
    });
  }
}

/** The person being asked must be a live, named user other than the requester. */
export async function loadRequestPayer(payerUserId: string, requesterUserId: string): Promise<{ id: string; displayName: string }> {
  if (payerUserId === requesterUserId) {
    throw new HttpError(400, "self_request", "You can't ask yourself for money.");
  }
  const payer = await prisma.user.findUnique({ where: { id: payerUserId }, select: { id: true, displayName: true, deletedAt: true } });
  if (!payer || payer.deletedAt || payer.displayName === "") {
    throw new HttpError(404, "payer_not_found", "We couldn't find that person on Quid.");
  }
  return { id: payer.id, displayName: payer.displayName };
}

/** A request is paid in one payment, so it can never be larger than the per-payment limit. */
export function assertRequestAmount(amountMinor: number): void {
  if (!Number.isInteger(amountMinor) || amountMinor <= 0) {
    throw new HttpError(400, "invalid_amount", "Enter an amount to ask for.");
  }
  if (amountMinor > LIMITS.perPaymentMinor) {
    throw new HttpError(400, "request_over_limit", `You can ask each person for up to ${pounds(LIMITS.perPaymentMinor)}, the most they can send in one payment.`, {
      limitMinor: LIMITS.perPaymentMinor,
    });
  }
}

export function normaliseTitle(raw: string): string {
  const tidy = raw.trim().replace(/\s+/g, " ");
  if (tidy.length === 0) {
    throw new HttpError(400, "invalid_title", "Give it a title, like “Pizza night”.");
  }
  if (tidy.length > LIMITS.requestTitleMaxLength) {
    throw new HttpError(400, "invalid_title", `Keep the title to ${LIMITS.requestTitleMaxLength} characters.`);
  }
  return tidy;
}

export function normaliseNote(raw: string | null | undefined): string | null {
  if (raw === null || raw === undefined) return null;
  const tidy = raw.trim().replace(/\s+/g, " ");
  if (tidy.length === 0) return null;
  if (tidy.length > LIMITS.requestNoteMaxLength) {
    throw new HttpError(400, "invalid_note", `Keep the note to ${LIMITS.requestNoteMaxLength} characters.`);
  }
  return tidy;
}

/**
 * A split's payment reference, from its title: accents folded ("Café" -> "Cafe"), anything outside the Faster
 * Payments set dropped, cut to 18 characters. Same rule as the app's reference field.
 */
export function referenceFromTitle(title: string): string {
  const folded = title.normalize("NFD").replace(/[̀-ͯ]/g, "");
  const kept = folded
    .replace(/[^A-Za-z0-9 &./-]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, LIMITS.referenceMaxLength)
    .trim();
  return kept.length > 0 ? kept : "Quid split";
}

/** Why a request can no longer be paid, declined or nudged. */
export function notPendingError(status: RequestStatus): HttpError {
  const messages: Record<RequestStatus, string> = {
    PENDING: "This request is still open.",
    PAID: "This request has already been paid.",
    DECLINED: "This request was declined.",
    EXPIRED: "This request has expired.",
  };
  return new HttpError(409, "request_not_pending", messages[status], { status });
}
