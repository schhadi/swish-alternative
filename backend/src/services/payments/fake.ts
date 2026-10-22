import { randomUUID } from "node:crypto";
import { ProviderError, type CreatePaymentInput, type CreatedProviderPayment, type PaymentProvider, type ProviderPaymentState, type ProviderStatus } from "./provider.js";

interface FakeRecord {
  state: ProviderPaymentState;
  amountMinor: number;
  accountHolderName: string;
  reference: string;
  providerSelection: CreatePaymentInput["providerSelection"];
  resourceToken: string;
  returnUri: string;
}

/**
 * Development and test stand-in for TrueLayer: payments live in memory and are moved along by the dev approval page
 * (routes/dev.ts) or by tests. Never configured in production (config.ts refuses PAYMENT_PROVIDER=fake there).
 */
export class FakePaymentProvider implements PaymentProvider {
  private readonly records = new Map<string, FakeRecord>();
  /** Tests flip this to exercise the provider-down path. */
  failNextCreate: ProviderError | null = null;

  constructor(private readonly publicBaseUrl: string) {}

  async createPayment(input: CreatePaymentInput): Promise<CreatedProviderPayment> {
    if (this.failNextCreate) {
      const error = this.failNextCreate;
      this.failNextCreate = null;
      throw error;
    }
    const providerPaymentId = `fake_${randomUUID()}`;
    const resourceToken = `fake_token_${randomUUID()}`;
    const providerId = input.providerSelection.type === "preselected" ? input.providerSelection.providerId : null;
    this.records.set(providerPaymentId, {
      state: { status: "authorization_required", failureReason: null, providerId },
      amountMinor: input.amountMinor,
      accountHolderName: input.beneficiary.accountHolderName,
      reference: input.reference,
      providerSelection: input.providerSelection,
      resourceToken,
      returnUri: input.returnUri,
    });
    return {
      providerPaymentId,
      resourceToken,
      authorisationUrl: `${this.publicBaseUrl}/dev/authorise/${providerPaymentId}`,
      status: "authorization_required",
    };
  }

  async getPayment(providerPaymentId: string): Promise<ProviderPaymentState> {
    const record = this.records.get(providerPaymentId);
    if (!record) throw new ProviderError("fake payment not found", 404, "not_found");
    return { ...record.state };
  }

  /** What the dev page shows: never the account identifiers. */
  describe(providerPaymentId: string): { amountMinor: number; accountHolderName: string; reference: string; status: ProviderStatus } | null {
    const record = this.records.get(providerPaymentId);
    if (!record) return null;
    return { amountMinor: record.amountMinor, accountHolderName: record.accountHolderName, reference: record.reference, status: record.state.status };
  }

  /**
   * Where the approval page sends the payer afterwards: the payment's own return URI with `payment_id` added, as the
   * hosted payment page is expected to do (docs/DECISIONS.md #59). The app's quid:// return and the web return page
   * for people paying a collection link both work this way.
   */
  returnTo(providerPaymentId: string): string | null {
    const record = this.records.get(providerPaymentId);
    if (!record) return null;
    const separator = record.returnUri.includes("?") ? "&" : "?";
    return `${record.returnUri}${separator}payment_id=${encodeURIComponent(providerPaymentId)}`;
  }

  advance(providerPaymentId: string, status: ProviderStatus, failureReason: string | null = null, providerId?: string | null): boolean {
    const record = this.records.get(providerPaymentId);
    if (!record) return false;
    record.state = {
      status,
      failureReason: status === "failed" ? failureReason ?? "failed" : null,
      providerId: providerId === undefined ? record.state.providerId : providerId,
    };
    return true;
  }
}
