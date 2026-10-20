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
