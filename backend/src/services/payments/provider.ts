import type { PaymentStatus } from "@prisma/client";

/**
 * The payment initiation provider behind POST /payments (docs/SPEC.md section 3). TrueLayer in sandbox and
 * production; an in-process fake for local development and tests. Beneficiary details pass through here in
 * plaintext and must never be logged.
 */
export type ProviderStatus = "authorization_required" | "authorizing" | "authorized" | "executed" | "settled" | "failed";

export interface CreatePaymentInput {
  /** Our payment id; also the Idempotency-Key, so a retried call can never create a second provider payment. */
  paymentId: string;
  amountMinor: number;
  currency: "GBP";
  reference: string;
  beneficiary: { accountHolderName: string; sortCode: string; accountNumber: string };
  payer: { id: string; name: string; phoneE164: string | null };
  providerSelection: { type: "preselected"; providerId: string } | { type: "user_selected" };
  returnUri: string;
}

export interface CreatedProviderPayment {
  providerPaymentId: string;
  resourceToken: string;
  /** Hosted payment page, for the app's web fallback and for people without the app (Phase 4). */
  authorisationUrl: string | null;
  status: ProviderStatus;
}

export interface ProviderPaymentState {
  status: ProviderStatus;
  failureReason: string | null;
  /** The bank the payer chose, once known. */
  providerId: string | null;
}

export interface PaymentProvider {
  createPayment(input: CreatePaymentInput): Promise<CreatedProviderPayment>;
  getPayment(providerPaymentId: string): Promise<ProviderPaymentState>;
  /**
   * Asks the provider to cancel a payment the payer has not completed. Resolving means the request was accepted, not
   * that the payment is cancelled: the outcome is read back with getPayment (and arrives by webhook). A 4xx
   * ProviderError means the payment is no longer cancellable.
   */
  cancelPayment(providerPaymentId: string): Promise<void>;
}

/** Raised for any provider failure; carries no request or response body, only what is safe to log. */
export class ProviderError extends Error {
  constructor(
    message: string,
    public readonly httpStatus: number | null = null,
    public readonly providerCode: string | null = null,
  ) {
    super(message);
    this.name = "ProviderError";
  }
}

const CANCELLED_PATTERN = /cancel/i;

/** Provider status -> ours. A failure the payer caused by backing out is CANCELLED, every other failure is FAILED. */
export function toPaymentStatus(state: Pick<ProviderPaymentState, "status" | "failureReason">): { status: PaymentStatus; failureReason: string | null } {
  switch (state.status) {
    case "authorization_required":
    case "authorizing":
      return { status: "AUTHORIZING", failureReason: null };
    case "authorized":
      return { status: "AUTHORIZED", failureReason: null };
    case "executed":
      return { status: "EXECUTED", failureReason: null };
    case "settled":
      return { status: "SETTLED", failureReason: null };
    case "failed":
      return {
        status: state.failureReason && CANCELLED_PATTERN.test(state.failureReason) ? "CANCELLED" : "FAILED",
        failureReason: state.failureReason ?? "failed",
      };
  }
}
