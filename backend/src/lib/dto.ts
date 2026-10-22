import { env } from "../config.js";
import { effectiveRequestStatus, nextReminderAt } from "../services/requests/rules.js";
import type { RequestRow, SplitRow } from "../services/requests/service.js";
import type { Payment, User } from "@prisma/client";
import { LIMITS } from "../limits.js";
import { providerDisplayName, type Provider } from "../services/providers.js";

/** What the app may know about a user. Never the phone hash. */
export function publicUser(user: Pick<User, "id" | "phoneE164" | "displayName" | "createdAt">) {
  return {
    id: user.id,
    phoneE164: user.phoneE164,
    displayName: user.displayName,
    createdAt: user.createdAt.toISOString(),
  };
}

export function limitsDTO() {
  return {
    perPaymentMinor: LIMITS.perPaymentMinor,
    rolling24hMinor: LIMITS.rolling24hMinor,
    rolling30dMinor: LIMITS.rolling30dMinor,
  };
}

/** "Priya Patel" -> "PP"; used so a contact can be labelled before the user taps it. */
export function initials(displayName: string): string {
  const parts = displayName.trim().split(/\s+/).filter(Boolean).slice(0, 2);
  return parts.map((part) => part.charAt(0).toUpperCase()).join("");
}

type PaymentWithParties = Payment & {
  payer: Pick<User, "id" | "displayName"> | null;
  payee: Pick<User, "id" | "displayName"> | null;
  collection: { org: { name: string } } | null;
};

/** Wire shape the app decodes (ios PaymentDTO). `counterparty` is the other side from the viewer's point of view. */
export function paymentDTO(payment: PaymentWithParties, viewerUserId: string, providers: readonly Provider[] = []) {
  const viewerIsPayer = payment.payerUserId === viewerUserId;
  let counterparty: { userId: string | null; displayName: string };
  if (viewerIsPayer) {
    if (payment.payee) counterparty = { userId: payment.payee.id, displayName: payment.payee.displayName };
    else if (payment.collection) counterparty = { userId: null, displayName: payment.collection.org.name };
    else counterparty = { userId: null, displayName: "Unknown" };
  } else if (payment.payer) {
    counterparty = { userId: payment.payer.id, displayName: payment.payer.displayName };
  } else {
    counterparty = { userId: null, displayName: payment.payerDisplayName ?? "Someone" };
  }
  return {
    id: payment.id,
    payerUserId: payment.payerUserId,
    payeeUserId: payment.payeeUserId,
    collectionId: payment.collectionId,
    requestId: payment.requestId,
    amountMinor: payment.amountMinor,
    currency: payment.currency,
    reference: payment.reference,
    status: payment.status,
    failureReason: payment.failureReason,
    createdAt: payment.createdAt.toISOString(),
    updatedAt: payment.updatedAt.toISOString(),
    settledAt: payment.settledAt?.toISOString() ?? null,
    counterparty,
    bankName: providerDisplayName(payment.providerId, providers),
  };
}

// ---------- Phase 3: requests and splits ----------


/** Wire shape the app decodes (ios PaymentRequestDTO). Both parties see the same fields. */
export function requestDTO(row: RequestRow, now: Date = new Date()) {
  return {
    id: row.id,
    requesterUserId: row.requesterUserId,
    payerUserId: row.payerUserId,
    amountMinor: row.amountMinor,
    reference: row.reference,
    note: row.note,
    status: effectiveRequestStatus(row, now),
    paymentId: row.paymentId,
    expiresAt: row.expiresAt.toISOString(),
    createdAt: row.createdAt.toISOString(),
    requester: { userId: row.requester.id, displayName: row.requester.displayName },
    payer: { userId: row.payer.id, displayName: row.payer.displayName },
    splitId: row.splitShare?.split.id ?? null,
    splitTitle: row.splitShare?.split.title ?? null,
    paidAt: row.paidAt?.toISOString() ?? null,
    declinedAt: row.declinedAt?.toISOString() ?? null,
    lastRemindedAt: row.lastRemindedAt?.toISOString() ?? null,
    remindCount: row.remindCount,
    nextReminderAt: nextReminderAt(row)?.toISOString() ?? null,
  };
}

/** The link the creator shares; it opens a page that hands over to the app (routes/links.ts). */
export function splitLink(splitId: string): string {
  return `${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/s/${splitId}`;
}

/** Creator's view of a split (ios SplitDTO): progress plus every share's state, people sorted by name. */
export function splitDTO(split: SplitRow, now: Date = new Date()) {
  const shares = [...split.shares]
    .sort((a, b) => a.user.displayName.localeCompare(b.user.displayName, "en-GB"))
    .map((share) => ({
      id: share.id,
      requestId: share.requestId,
      userId: share.user.id,
      displayName: share.user.displayName,
      amountMinor: share.amountMinor,
      status: effectiveRequestStatus(share.request, now),
      paymentId: share.request.paymentId,
      paidAt: share.request.paidAt?.toISOString() ?? null,
      declinedAt: share.request.declinedAt?.toISOString() ?? null,
      lastRemindedAt: share.request.lastRemindedAt?.toISOString() ?? null,
      remindCount: share.request.remindCount,
      nextReminderAt: nextReminderAt(share.request)?.toISOString() ?? null,
    }));
  const requestedMinor = shares.reduce((sum, share) => sum + share.amountMinor, 0);
  const paid = shares.filter((share) => share.status === "PAID");
  const pendingCount = shares.filter((share) => share.status === "PENDING").length;
  return {
    id: split.id,
    title: split.title,
    totalMinor: split.totalMinor,
    createdAt: split.createdAt.toISOString(),
    creatorShareMinor: Math.max(0, split.totalMinor - requestedMinor),
    requestedMinor,
    paidMinor: paid.reduce((sum, share) => sum + share.amountMinor, 0),
    shareCount: shares.length,
    paidCount: paid.length,
    pendingCount,
    isComplete: pendingCount === 0,
    link: splitLink(split.id),
    shares,
  };
}
