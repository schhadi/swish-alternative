import type { Payment } from "@prisma/client";
import type { FastifyBaseLogger } from "fastify";
import { env } from "../../config.js";
import { prisma } from "../../lib/db.js";
import { HttpError } from "../../lib/errors.js";
import { withKeyedLock } from "../../lib/keyedLock.js";
import { decryptBankDetails, userOwnerKey } from "../bankAccounts.js";
import { ProviderError, type PaymentProvider } from "./provider.js";
import { effectiveRequestStatus, notPendingError } from "../requests/rules.js";
import { assertWithinLimits, isFirstTimePayee, loadPayableUser, normaliseReference, pounds } from "./rules.js";
import { applyTransition } from "./stateMachine.js";

/** Either a payee, amount and reference typed by the payer, or a request to pay (which fixes all three). */
export type CreatePeerPaymentInput = {
  payer: { id: string; displayName: string; phoneE164: string | null };
  now?: Date;
} & (
  | { requestId?: undefined; payeeUserId: string; amountMinor: number; reference: string }
  | { requestId: string; amountMinor?: number }
);

export interface CreatedPeerPayment {
  payment: Payment;
  resourceToken: string;
  authorisationUrl: string | null;
  firstTimePayee: boolean;
  payee: { userId: string; displayName: string; accountHolderName: string; copStatus: string; providerId: string | null };
}

/**
 * POST /payments for a person-to-person payment (docs/SPEC.md sections 3, 5, 7). Order matters:
 * 1. rules + limits + the CREATED row, serialised per payer, so the amount counts against the windows before the
 *    next request from the same payer is checked;
 * 2. the provider call outside the lock, with our id as the Idempotency-Key;
 * 3. the row updated to AUTHORIZING, or FAILED with provider_error when the provider refused.
 * Bank details are decrypted here and handed to the provider only; nothing in this function logs them.
 */
export async function createPeerPayment(provider: PaymentProvider, input: CreatePeerPaymentInput, log: FastifyBaseLogger): Promise<CreatedPeerPayment> {
  const now = input.now ?? new Date();
  if (input.requestId === undefined) {
    if (!Number.isInteger(input.amountMinor) || input.amountMinor <= 0) {
      throw new HttpError(400, "invalid_amount", "Enter an amount to send.");
    }
  }
  const typedReference = input.requestId === undefined ? normaliseReference(input.reference) : null;

  const prepared = await withKeyedLock(`payer:${input.payer.id}`, async () => {
    const tx = prisma;
    // Paying a request: the payee, amount and reference come from the request, which must still be open.
    const terms = input.requestId === undefined
      ? { payeeUserId: input.payeeUserId, amountMinor: input.amountMinor, reference: typedReference as string, requestId: null }
      : await loadPayableRequest(input.requestId, input.payer.id, input.amountMinor, now);
    const payee = await loadPayableUser(tx, terms.payeeUserId, input.payer.id, now);
    await assertWithinLimits(tx, input.payer.id, terms.amountMinor, now);
    const firstTimePayee = await isFirstTimePayee(tx, input.payer.id, payee.id);
    const payerBank = await tx.bankAccount.findUnique({ where: { userId: input.payer.id }, select: { providerId: true } });
    const payment = await tx.payment.create({
      data: {
        payerUserId: input.payer.id,
        payeeUserId: payee.id,
        requestId: terms.requestId,
        amountMinor: terms.amountMinor,
        currency: "GBP",
        reference: terms.reference,
        status: "CREATED",
        providerId: payerBank?.providerId ?? null,
        createdAt: now,
      },
    });
    return { payee, payment, firstTimePayee, payerProviderId: payerBank?.providerId ?? null };
  });
  const amountMinor = prepared.payment.amountMinor;
  const reference = prepared.payment.reference;

  const { created, beneficiary } = await sendToProvider(
    provider,
    {
      paymentId: prepared.payment.id,
      amountMinor,
      reference,
      beneficiary: () => decryptBankDetails(userOwnerKey(prepared.payee.id), prepared.payee.bankAccount),
      payer: { id: input.payer.id, name: input.payer.displayName, phoneE164: input.payer.phoneE164 },
      providerSelection: prepared.payerProviderId ? { type: "preselected", providerId: prepared.payerProviderId } : { type: "user_selected" },
      returnUri: env.PAYMENT_RETURN_URI,
    },
    log,
  );
  const payment = await prisma.payment.findUniqueOrThrow({ where: { id: prepared.payment.id } });

  return {
    payment,
    resourceToken: created.resourceToken,
    authorisationUrl: created.authorisationUrl,
    firstTimePayee: prepared.firstTimePayee,
    payee: {
      userId: prepared.payee.id,
      displayName: prepared.payee.displayName,
      accountHolderName: beneficiary.accountHolderName,
      copStatus: prepared.payee.bankAccount.copStatus,
      providerId: prepared.payee.bankAccount.providerId,
    },
  };
}

/**
 * The request being paid: addressed to this payer and still open. More than one payment may be started for the same
 * request (a cancelled attempt followed by another); the first to execute pays it (docs/DECISIONS.md #74).
 */
async function loadPayableRequest(requestId: string, payerUserId: string, amountMinor: number | undefined, now: Date) {
  const request = await prisma.paymentRequest.findUnique({ where: { id: requestId } });
  if (!request || request.payerUserId !== payerUserId) {
    throw new HttpError(404, "request_not_found", "We couldn't find that request.");
  }
  const status = effectiveRequestStatus(request, now);
  if (status !== "PENDING") {
    throw notPendingError(status);
  }
  if (amountMinor !== undefined && amountMinor !== request.amountMinor) {
    throw new HttpError(400, "request_amount_mismatch", `This request is for ${pounds(request.amountMinor)}.`, { amountMinor: request.amountMinor });
  }
  return { payeeUserId: request.requesterUserId, amountMinor: request.amountMinor, reference: request.reference, requestId: request.id };
}

export interface ProviderCall {
  paymentId: string;
  amountMinor: number;
  reference: string;
  /** Decrypts the payee's details; called inside the failure guard, so a key problem ends as FAILED + 502. */
  beneficiary: () => { accountHolderName: string; sortCode: string; accountNumber: string };
  payer: { id: string; name: string; phoneE164: string | null };
  providerSelection: { type: "preselected"; providerId: string } | { type: "user_selected" };
  returnUri: string;
}

/**
 * Hands a CREATED row to the provider, with our id as the Idempotency-Key, and moves it to AUTHORIZING. When the
 * provider (or decryption) fails the row becomes FAILED with provider_error and the caller gets a 502, so a failed
 * start never keeps counting against the payer's limits. Shared by person-to-person and collection payments.
 */
export async function sendToProvider(provider: PaymentProvider, call: ProviderCall, log: FastifyBaseLogger) {
  let created;
  let beneficiary;
  try {
    beneficiary = call.beneficiary();
    created = await provider.createPayment({
      paymentId: call.paymentId,
      amountMinor: call.amountMinor,
      currency: "GBP",
      reference: call.reference,
      beneficiary,
      payer: call.payer,
      providerSelection: call.providerSelection,
      returnUri: call.returnUri,
    });
  } catch (error) {
    const providerError = error instanceof ProviderError ? error : null;
    log.error(
      { paymentId: call.paymentId, httpStatus: providerError?.httpStatus, providerCode: providerError?.providerCode ?? (providerError ? null : "internal") },
      "payment provider refused to create the payment",
    );
    await applyTransition(call.paymentId, { to: "FAILED", source: "user", failureReason: "provider_error" }, log);
    throw new HttpError(502, "payment_provider_unavailable", "We couldn't start the payment with your bank just now. Nothing has been sent; try again in a moment.");
  }
  await prisma.payment.update({
    where: { id: call.paymentId },
    data: { tlPaymentId: created.providerPaymentId, providerStatus: created.status },
  });
  await applyTransition(call.paymentId, { to: "AUTHORIZING", source: "user" }, log);
  return { created, beneficiary };
}
