import type { Payment } from "@prisma/client";
import type { FastifyBaseLogger } from "fastify";
import { env } from "../../config.js";
import { prisma } from "../../lib/db.js";
import { HttpError } from "../../lib/errors.js";
import { withKeyedLock } from "../../lib/keyedLock.js";
import { decryptBankDetails, userOwnerKey } from "../bankAccounts.js";
import { ProviderError, type PaymentProvider } from "./provider.js";
import { assertWithinLimits, isFirstTimePayee, loadPayableUser, normaliseReference } from "./rules.js";
import { applyTransition } from "./stateMachine.js";

export interface CreatePeerPaymentInput {
  payer: { id: string; displayName: string; phoneE164: string | null };
  payeeUserId: string;
  amountMinor: number;
  reference: string;
  now?: Date;
}

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
  const reference = normaliseReference(input.reference);
  if (!Number.isInteger(input.amountMinor) || input.amountMinor <= 0) {
    throw new HttpError(400, "invalid_amount", "Enter an amount to send.");
  }

  const prepared = await withKeyedLock(`payer:${input.payer.id}`, async () => {
    const tx = prisma;
    const payee = await loadPayableUser(tx, input.payeeUserId, input.payer.id, now);
    await assertWithinLimits(tx, input.payer.id, input.amountMinor, now);
    const firstTimePayee = await isFirstTimePayee(tx, input.payer.id, payee.id);
    const payerBank = await tx.bankAccount.findUnique({ where: { userId: input.payer.id }, select: { providerId: true } });
    const payment = await tx.payment.create({
      data: {
        payerUserId: input.payer.id,
        payeeUserId: payee.id,
        amountMinor: input.amountMinor,
        currency: "GBP",
        reference,
        status: "CREATED",
        providerId: payerBank?.providerId ?? null,
        createdAt: now,
      },
    });
    return { payee, payment, firstTimePayee, payerProviderId: payerBank?.providerId ?? null };
  });

  const beneficiary = decryptBankDetails(userOwnerKey(prepared.payee.id), prepared.payee.bankAccount);
  let created;
  try {
    created = await provider.createPayment({
      paymentId: prepared.payment.id,
      amountMinor: input.amountMinor,
      currency: "GBP",
      reference,
      beneficiary,
      payer: { id: input.payer.id, name: input.payer.displayName, phoneE164: input.payer.phoneE164 },
      providerSelection: prepared.payerProviderId ? { type: "preselected", providerId: prepared.payerProviderId } : { type: "user_selected" },
      returnUri: env.PAYMENT_RETURN_URI,
    });
  } catch (error) {
    const providerError = error instanceof ProviderError ? error : null;
    log.error({ paymentId: prepared.payment.id, httpStatus: providerError?.httpStatus, providerCode: providerError?.providerCode }, "payment provider refused to create the payment");
    await applyTransition(prepared.payment.id, { to: "FAILED", source: "user", failureReason: "provider_error" }, log);
    throw new HttpError(502, "payment_provider_unavailable", "We couldn't start the payment with your bank just now. Nothing has been sent; try again in a moment.");
  }

  await prisma.payment.update({
    where: { id: prepared.payment.id },
    data: { tlPaymentId: created.providerPaymentId, providerStatus: created.status },
  });
  await applyTransition(prepared.payment.id, { to: "AUTHORIZING", source: "user" }, log);
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
