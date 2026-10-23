import type { PaymentStatus } from "@prisma/client";
import type { FastifyBaseLogger } from "fastify";
import { prisma } from "../../lib/db.js";
import { HttpError } from "../../lib/errors.js";
import { reconcilePayment } from "./poller.js";
import { ProviderError, type PaymentProvider } from "./provider.js";

/** Before the payer has approved at their bank. Once they have (AUTHORIZED), the bank is sending it. */
const CANCELLABLE: ReadonlySet<PaymentStatus> = new Set(["CREATED", "AUTHORIZING"]);
const SENT: ReadonlySet<PaymentStatus> = new Set(["EXECUTED", "SETTLED"]);

const notCancellable = () => new HttpError(409, "payment_not_cancellable", "This payment has already gone through, so it can't be cancelled.");
const alreadyApproved = () => new HttpError(409, "payment_not_cancellable", "You've approved this payment at your bank, so it can't be cancelled now.");

/**
 * The payer backs out before finishing at the bank (docs/DECISIONS.md #92): the first-time-payee sheet's Cancel, or
 * the bank reporting that they cancelled. Our row becomes CANCELLED only once the provider says so, read straight
 * back after the cancel call, so a payment the bank executes anyway is never marked cancelled. With TrueLayer the
 * cancel is asynchronous: if it has not landed by the read-back, the webhook or the fallback poll applies it.
 * Already failed or cancelled: nothing to do. Approved at the bank, or sent: 409, and the provider is not asked.
 * A provider refusal is trusted only when the read-back shows the payment past the point of cancelling; a refusal
 * of a payment still waiting for the payer means our request was wrong, so it warns and answers 502.
 */
export async function cancelPaymentForPayer(provider: PaymentProvider, paymentId: string, payerUserId: string, log: FastifyBaseLogger, now: Date = new Date()): Promise<void> {
  const payment = await prisma.payment.findFirst({ where: { id: paymentId, payerUserId }, select: { id: true, status: true, tlPaymentId: true } });
  if (!payment) {
    throw new HttpError(404, "not_found", "We couldn't find that payment.");
  }
  if (SENT.has(payment.status)) throw notCancellable();
  if (payment.status === "AUTHORIZED") throw alreadyApproved();
  if (!CANCELLABLE.has(payment.status)) return;
  if (!payment.tlPaymentId) {
    // The provider call is still running (or the process died during it; the abandoned-creation sweep fails it).
    throw new HttpError(409, "payment_starting", "This payment is still being set up. Try again in a moment.");
  }

  log.info({ paymentId }, "payment cancel requested by payer");
  let refusal: ProviderError | null = null;
  try {
    await provider.cancelPayment(payment.tlPaymentId);
  } catch (error) {
    const refused = error instanceof ProviderError && error.httpStatus !== null && error.httpStatus >= 400 && error.httpStatus < 500;
    if (!refused) {
      log.warn({ paymentId, err: error }, "payment cancel failed at the provider");
      throw unavailable();
    }
    refusal = error;
  }
  await reconcilePayment(payment.id, payment.tlPaymentId, provider, "user", log, now);
  const after = await prisma.payment.findUniqueOrThrow({ where: { id: payment.id }, select: { status: true } });
  if (SENT.has(after.status)) throw notCancellable();
  if (refusal) {
    if (after.status === "AUTHORIZED") throw alreadyApproved();
    if (CANCELLABLE.has(after.status)) {
      // Still waiting for the payer, yet refused: our cancel call itself is wrong (docs/DECISIONS.md #59) or limited.
      log.warn({ paymentId, httpStatus: refusal.httpStatus, providerCode: refusal.providerCode }, "payment cancel refused while still cancellable");
      throw unavailable();
    }
    log.info({ paymentId, httpStatus: refusal.httpStatus, status: after.status }, "payment cancel refused; it had already ended");
  }
}

function unavailable() {
  return new HttpError(502, "payment_provider_unavailable", "We couldn't cancel it with your bank's payment service just now. Nothing has been sent; try again in a moment.");
}
