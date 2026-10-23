import { randomUUID } from "node:crypto";
import type { Prisma } from "@prisma/client";
import type { FastifyBaseLogger } from "fastify";
import { prisma } from "../../lib/db.js";
import { HttpError } from "../../lib/errors.js";
import { ukDateTime } from "../../lib/time.js";
import { LIMITS } from "../../limits.js";
import { normaliseReference, pounds } from "../payments/rules.js";
import { pushStub } from "../push.js";
import {
  assertRequestAmount,
  assertRequesterCanReceive,
  effectiveRequestStatus,
  loadRequestPayer,
  nextReminderAt,
  normaliseNote,
  normaliseTitle,
  notPendingError,
  referenceFromTitle,
  requestExpiry,
} from "./rules.js";

/** Requests and splits (docs/SPEC.md section 5). Ids, never names or numbers, go to the log. */

export const requestInclude = {
  requester: { select: { id: true, displayName: true } },
  payer: { select: { id: true, displayName: true } },
  splitShare: { select: { split: { select: { id: true, title: true } } } },
} as const;

export type RequestRow = Prisma.PaymentRequestGetPayload<{ include: typeof requestInclude }>;

export const splitInclude = {
  shares: {
    include: {
      user: { select: { id: true, displayName: true } },
      request: true,
    },
  },
} as const;

export type SplitRow = Prisma.SplitGetPayload<{ include: typeof splitInclude }>;

const HOUR_MS = 60 * 60 * 1000;

export interface CreateRequestInput {
  requesterUserId: string;
  payerUserId: string;
  amountMinor: number;
  reference: string;
  note?: string | null;
  now?: Date;
}

/** POST /requests: one person asked for one amount. */
export async function createRequest(input: CreateRequestInput, log: FastifyBaseLogger): Promise<RequestRow> {
  const now = input.now ?? new Date();
  assertRequestAmount(input.amountMinor);
  const reference = normaliseReference(input.reference);
  const note = normaliseNote(input.note);
  await assertRequesterCanReceive(input.requesterUserId, now);
  const payer = await loadRequestPayer(input.payerUserId, input.requesterUserId);
  const row = await prisma.paymentRequest.create({
    data: {
      requesterUserId: input.requesterUserId,
      payerUserId: payer.id,
      amountMinor: input.amountMinor,
      reference,
      note,
      expiresAt: requestExpiry(now),
      createdAt: now,
    },
    include: requestInclude,
  });
  log.info({ requestId: row.id, requesterUserId: input.requesterUserId, payerUserId: payer.id }, "payment request created");
  pushStub(log, "request_received", [payer.id], { requestId: row.id });
  return row;
}

export interface CreateSplitInput {
  creatorUserId: string;
  title: string;
  totalMinor: number;
  shares: readonly { userId: string; amountMinor: number }[];
  now?: Date;
}

/**
 * POST /splits: one PaymentRequest per share, written together. `totalMinor` is the whole bill; what the shares do
 * not cover is the creator's own part (docs/DECISIONS.md #73).
 */
export async function createSplit(input: CreateSplitInput, log: FastifyBaseLogger): Promise<string> {
  const now = input.now ?? new Date();
  const title = normaliseTitle(input.title);
  if (!Number.isInteger(input.totalMinor) || input.totalMinor <= 0) {
    throw new HttpError(400, "invalid_amount", "Enter the total to split.");
  }
  if (input.totalMinor > LIMITS.splitMaxTotalMinor) {
    throw new HttpError(400, "split_total_too_large", `A split can be for up to ${pounds(LIMITS.splitMaxTotalMinor)}.`);
  }
  if (input.shares.length === 0) {
    throw new HttpError(400, "split_no_people", "Choose at least one person to ask.");
  }
  if (input.shares.length > LIMITS.splitMaxShares) {
    throw new HttpError(400, "split_too_many_people", `You can ask up to ${LIMITS.splitMaxShares} people at once.`);
  }
  const userIds = new Set<string>();
  for (const share of input.shares) {
    if (userIds.has(share.userId)) {
      throw new HttpError(400, "split_duplicate_person", "Each person can only be in a split once.");
    }
    userIds.add(share.userId);
    if (share.userId === input.creatorUserId) {
      throw new HttpError(400, "self_request", "You can't ask yourself for money.");
    }
    assertRequestAmount(share.amountMinor);
  }
  const requested = input.shares.reduce((sum, share) => sum + share.amountMinor, 0);
  if (requested > input.totalMinor) {
    throw new HttpError(400, "split_shares_exceed_total", "The shares add up to more than the total.");
  }
  await assertRequesterCanReceive(input.creatorUserId, now);
  const payers = await prisma.user.findMany({ where: { id: { in: [...userIds] } }, select: { id: true, displayName: true, deletedAt: true } });
  const live = new Set(payers.filter((payer) => !payer.deletedAt && payer.displayName !== "").map((payer) => payer.id));
  if ([...userIds].some((id) => !live.has(id))) {
    throw new HttpError(404, "payer_not_found", "We couldn't find one of those people on Quid.");
  }

  const reference = referenceFromTitle(title);
  const expiresAt = requestExpiry(now);
  const splitId = randomUUID();
  const rows = input.shares.map((share) => ({ ...share, requestId: randomUUID(), shareId: randomUUID() }));
  await prisma.$transaction([
    prisma.split.create({ data: { id: splitId, creatorUserId: input.creatorUserId, title, totalMinor: input.totalMinor, createdAt: now } }),
    ...rows.map((row) =>
      prisma.paymentRequest.create({
        data: {
          id: row.requestId,
          requesterUserId: input.creatorUserId,
          payerUserId: row.userId,
          amountMinor: row.amountMinor,
          reference,
          expiresAt,
          createdAt: now,
        },
      }),
    ),
    ...rows.map((row) => prisma.splitShare.create({ data: { id: row.shareId, splitId, userId: row.userId, amountMinor: row.amountMinor, requestId: row.requestId } })),
  ]);
  log.info({ splitId, creatorUserId: input.creatorUserId, shareCount: rows.length }, "split created");
  for (const row of rows) {
    pushStub(log, "request_received", [row.userId], { requestId: row.requestId, splitId });
  }
  return splitId;
}

/** The payer says no. Only an open request addressed to them can be declined. */
export async function declineRequest(requestId: string, userId: string, log: FastifyBaseLogger, now: Date = new Date()): Promise<void> {
  const result = await prisma.paymentRequest.updateMany({
    where: { id: requestId, payerUserId: userId, status: "PENDING", expiresAt: { gt: now } },
    data: { status: "DECLINED", declinedAt: now },
  });
  const row = await prisma.paymentRequest.findUnique({ where: { id: requestId }, select: { payerUserId: true, requesterUserId: true, status: true, expiresAt: true } });
  if (!row || row.payerUserId !== userId) {
    throw new HttpError(404, "request_not_found", "We couldn't find that request.");
  }
  if (result.count === 0) {
    throw notPendingError(effectiveRequestStatus(row, now));
  }
  log.info({ requestId }, "payment request declined");
  pushStub(log, "request_declined", [row.requesterUserId], { requestId });
}

/**
 * The requester withdraws an open request (docs/DECISIONS.md #91). A payment already at the bank still pays it: the
 * state machine marks any request PAID once its payment executes, whatever it said before.
 */
export async function cancelRequest(requestId: string, userId: string, log: FastifyBaseLogger, now: Date = new Date()): Promise<void> {
  const result = await prisma.paymentRequest.updateMany({
    where: { id: requestId, requesterUserId: userId, status: "PENDING", expiresAt: { gt: now } },
    data: { status: "CANCELLED", cancelledAt: now },
  });
  const row = await prisma.paymentRequest.findUnique({ where: { id: requestId }, select: { payerUserId: true, requesterUserId: true, status: true, expiresAt: true } });
  if (!row || row.requesterUserId !== userId) {
    throw new HttpError(404, "request_not_found", "We couldn't find that request.");
  }
  if (result.count === 0) {
    throw notPendingError(effectiveRequestStatus(row, now));
  }
  log.info({ requestId }, "payment request cancelled");
  pushStub(log, "request_cancelled", [row.payerUserId], { requestId });
}

/** Cancels every share of a split that is still open; paid, declined and expired shares stay as they are. */
export async function cancelSplit(splitId: string, userId: string, log: FastifyBaseLogger, now: Date = new Date()): Promise<{ cancelled: string[] }> {
  const split = await prisma.split.findUnique({ where: { id: splitId }, select: { creatorUserId: true, shares: { select: { requestId: true } } } });
  if (!split || split.creatorUserId !== userId) {
    throw new HttpError(404, "split_not_found", "We couldn't find that split.");
  }
  const cancelled: string[] = [];
  for (const { requestId } of split.shares) {
    try {
      await cancelRequest(requestId, userId, log, now);
      cancelled.push(requestId);
    } catch (error) {
      if (!(error instanceof HttpError) || error.code !== "request_not_pending") throw error;
    }
  }
  if (cancelled.length === 0) {
    throw new HttpError(409, "split_nothing_to_cancel", "Nobody in this split has anything left to pay.");
  }
  return { cancelled };
}

/**
 * The requester nudges the payer: at most once per 24 hours per request (docs/SPEC.md section 7). The condition is
 * part of the write, so two taps at once send one reminder.
 */
export async function remindRequest(requestId: string, userId: string, log: FastifyBaseLogger, now: Date = new Date()): Promise<void> {
  const windowStart = new Date(now.getTime() - LIMITS.reminderMinIntervalHours * HOUR_MS);
  const result = await prisma.paymentRequest.updateMany({
    where: {
      id: requestId,
      requesterUserId: userId,
      status: "PENDING",
      expiresAt: { gt: now },
      OR: [{ lastRemindedAt: null }, { lastRemindedAt: { lte: windowStart } }],
    },
    data: { lastRemindedAt: now, remindCount: { increment: 1 } },
  });
  const row = await prisma.paymentRequest.findUnique({
    where: { id: requestId },
    select: { requesterUserId: true, payerUserId: true, status: true, expiresAt: true, lastRemindedAt: true },
  });
  if (!row || row.requesterUserId !== userId) {
    throw new HttpError(404, "request_not_found", "We couldn't find that request.");
  }
  if (result.count === 1) {
    log.info({ requestId }, "payment request reminder sent");
    pushStub(log, "request_reminder", [row.payerUserId], { requestId });
    return;
  }
  const status = effectiveRequestStatus(row, now);
  if (status !== "PENDING") {
    throw notPendingError(status);
  }
  const next = nextReminderAt(row) ?? now;
  throw new HttpError(429, "remind_too_soon", `You've nudged them in the last day. You can nudge again from ${ukDateTime(next)}.`, {
    nextReminderAt: next.toISOString(),
  });
}

export interface SplitReminderResult {
  reminded: string[];
  skipped: { requestId: string; reason: "too_soon" | "not_pending"; nextReminderAt: string | null }[];
}

/** "Remind everyone unpaid": every open share (or the ones named) that is due a reminder; the rest are reported. */
export async function remindSplit(splitId: string, userId: string, requestIds: readonly string[] | undefined, log: FastifyBaseLogger, now: Date = new Date()): Promise<SplitReminderResult> {
  const split = await prisma.split.findUnique({ where: { id: splitId }, select: { creatorUserId: true, shares: { select: { requestId: true } } } });
  if (!split || split.creatorUserId !== userId) {
    throw new HttpError(404, "split_not_found", "We couldn't find that split.");
  }
  const wanted = requestIds ? new Set(requestIds) : null;
  const targets = split.shares.map((share) => share.requestId).filter((id) => !wanted || wanted.has(id));
  const outcome: SplitReminderResult = { reminded: [], skipped: [] };
  for (const requestId of targets) {
    try {
      await remindRequest(requestId, userId, log, now);
      outcome.reminded.push(requestId);
    } catch (error) {
      if (!(error instanceof HttpError)) throw error;
      if (error.code === "remind_too_soon") {
        outcome.skipped.push({ requestId, reason: "too_soon", nextReminderAt: String(error.details?.nextReminderAt ?? "") || null });
      } else if (error.code === "request_not_pending") {
        outcome.skipped.push({ requestId, reason: "not_pending", nextReminderAt: null });
      } else {
        throw error;
      }
    }
  }
  return outcome;
}

/** Marks open requests past their expiry as EXPIRED. Runs hourly; reads already treat them as expired. */
export async function expireStaleRequests(now: Date = new Date()): Promise<number> {
  const result = await prisma.paymentRequest.updateMany({ where: { status: "PENDING", expiresAt: { lte: now } }, data: { status: "EXPIRED" } });
  return result.count;
}

/** Account deletion closes every open request to or from the user; nobody can pay or be paid through them again. */
export function closeRequestsForDeletedUser(userId: string, now: Date = new Date()) {
  return prisma.paymentRequest.updateMany({
    where: { status: "PENDING", OR: [{ requesterUserId: userId }, { payerUserId: userId }] },
    data: { status: "EXPIRED", expiresAt: now },
  });
}
