import * as tlSigning from "truelayer-signing";
import type { HttpMethod } from "truelayer-signing";
import { LIMITS } from "../../limits.js";
import { ProviderError, type CreatePaymentInput, type CreatedProviderPayment, type PaymentProvider, type ProviderPaymentState, type ProviderStatus } from "../payments/provider.js";

/**
 * TrueLayer Payments API v3 client (docs/SPEC.md section 6).
 *
 * VERIFIED against TrueLayer's official sources (truelayer-signing repo and npm package 0.2.3): request signing
 * (Tl-Signature = detached ES512 JWS over "POST /v3/..." + the Idempotency-Key header + body), the Idempotency-Key
 * header, the sandbox API host https://api.truelayer-sandbox.com and the /v3 path prefix.
 *
 * NOT YET VERIFIED against docs.truelayer.com (unreachable from the machine this was written on; check before the
 * first sandbox run, docs/DECISIONS.md #59): the token endpoint path and form (connect/token, client_credentials,
 * scope "payments"), every field name in the create-payment body and response (resource_token, status), the
 * GET /v3/payments/{id} response (status, failure_reason, payment_method.provider_selection.provider_id), the raw
 * status vocabulary, the hosted payment page URL, the Idempotency-Key replay semantics (same response or 409,
 * byte-identical body, key lifetime; no retry is attempted until that is known) and the GB provider ids in
 * services/providers.ts (a preselected payment with an unknown id fails as 4xx -> FAILED -> 502, nothing is sent).
 * All of them live in this file only.
 */
export interface TrueLayerClientOptions {
  apiBaseUrl: string;
  authBaseUrl: string;
  hppBaseUrl: string;
  clientId: string;
  clientSecret: string;
  kid: string;
  privateKeyPem: string;
  fetch?: typeof fetch;
  now?: () => number;
}

interface TokenResponse {
  access_token: string;
  expires_in: number;
}

interface CreatePaymentResponse {
  id: string;
  resource_token: string;
  status: string;
}

interface GetPaymentResponse {
  id: string;
  status: string;
  failure_reason?: string;
  payment_method?: { provider_selection?: { provider_id?: string } };
}

const KNOWN_STATUSES: ReadonlySet<string> = new Set<ProviderStatus>(["authorization_required", "authorizing", "authorized", "executed", "settled", "failed"]);

export class TrueLayerClient implements PaymentProvider {
  private readonly fetchImpl: typeof fetch;
  private readonly now: () => number;
  private token: { value: string; expiresAt: number } | null = null;

  constructor(private readonly options: TrueLayerClientOptions) {
    this.fetchImpl = options.fetch ?? globalThis.fetch;
    this.now = options.now ?? (() => Date.now());
  }

  async createPayment(input: CreatePaymentInput): Promise<CreatedProviderPayment> {
    const body = JSON.stringify({
      amount_in_minor: input.amountMinor,
      currency: input.currency,
      payment_method: {
        type: "bank_transfer",
        provider_selection:
          input.providerSelection.type === "preselected"
            ? { type: "preselected", provider_id: input.providerSelection.providerId }
            : { type: "user_selected" },
        beneficiary: {
          type: "external_account",
          account_holder_name: input.beneficiary.accountHolderName,
          account_identifier: {
            type: "sort_code_account_number",
            sort_code: input.beneficiary.sortCode,
            account_number: input.beneficiary.accountNumber,
          },
          reference: input.reference,
        },
      },
      // name and phone_number are required for non-regulated clients (docs/SPEC.md section 6).
      user: {
        id: input.payer.id,
        name: input.payer.name,
        ...(input.payer.phoneE164 ? { phone_number: input.payer.phoneE164 } : {}),
      },
    });
    const path = "/v3/payments";
    const signature = tlSigning.sign({
      kid: this.options.kid,
      privateKeyPem: this.options.privateKeyPem,
      method: "POST" as unknown as HttpMethod,
      path,
      headers: { "Idempotency-Key": input.paymentId },
      body,
    });
    const response = await this.request<CreatePaymentResponse>("POST", path, {
      body,
      headers: { "Idempotency-Key": input.paymentId, "Tl-Signature": signature, "Content-Type": "application/json" },
    });
    return {
      providerPaymentId: response.id,
      resourceToken: response.resource_token,
      authorisationUrl: this.hostedPaymentPage(response.id, response.resource_token, input.returnUri),
      status: this.status(response.status),
    };
  }

  async getPayment(providerPaymentId: string): Promise<ProviderPaymentState> {
    const response = await this.request<GetPaymentResponse>("GET", `/v3/payments/${encodeURIComponent(providerPaymentId)}`);
    return {
      status: this.status(response.status),
      failureReason: response.failure_reason ?? null,
      providerId: response.payment_method?.provider_selection?.provider_id ?? null,
    };
  }

  hostedPaymentPage(paymentId: string, resourceToken: string, returnUri: string): string {
    const fragment = `payment_id=${encodeURIComponent(paymentId)}&resource_token=${encodeURIComponent(resourceToken)}&return_uri=${encodeURIComponent(returnUri)}`;
    return `${this.options.hppBaseUrl}/payments#${fragment}`;
  }

  private status(raw: string): ProviderStatus {
    if (KNOWN_STATUSES.has(raw)) return raw as ProviderStatus;
    throw new ProviderError(`unknown payment status from provider: ${raw}`, null, "unknown_status");
  }

  private async accessToken(): Promise<string> {
    if (this.token && this.token.expiresAt > this.now() + 60_000) return this.token.value;
    const form = new URLSearchParams({
      grant_type: "client_credentials",
      client_id: this.options.clientId,
      client_secret: this.options.clientSecret,
      scope: "payments",
    });
    let response: Response;
    try {
      response = await this.fetchImpl(`${this.options.authBaseUrl}/connect/token`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
        signal: AbortSignal.timeout(LIMITS.providerRequestTimeoutMs),
      });
    } catch (error) {
      throw new ProviderError(`token request failed: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (!response.ok) {
      throw new ProviderError("token request rejected", response.status, "token_rejected");
    }
    const parsed = (await response.json()) as Partial<TokenResponse>;
    if (!parsed.access_token || typeof parsed.expires_in !== "number") {
      throw new ProviderError("token response malformed", response.status, "token_malformed");
    }
    this.token = { value: parsed.access_token, expiresAt: this.now() + parsed.expires_in * 1000 };
    return this.token.value;
  }

  private async request<T>(method: "GET" | "POST", path: string, init: { body?: string; headers?: Record<string, string> } = {}): Promise<T> {
    const token = await this.accessToken();
    let response: Response;
    try {
      response = await this.fetchImpl(`${this.options.apiBaseUrl}${path}`, {
        method,
        headers: { Authorization: `Bearer ${token}`, Accept: "application/json", ...init.headers },
        ...(init.body !== undefined ? { body: init.body } : {}),
        signal: AbortSignal.timeout(LIMITS.providerRequestTimeoutMs),
      });
    } catch (error) {
      throw new ProviderError(`${method} ${path} failed: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (!response.ok) {
      // Error bodies may echo request data; keep only the status and TrueLayer's error type.
      let code: string | null = null;
      try {
        const problem = (await response.json()) as { type?: string; title?: string };
        code = problem.type ?? problem.title ?? null;
      } catch {
        // not JSON
      }
      throw new ProviderError(`${method} ${path} rejected`, response.status, code);
    }
    return (await response.json()) as T;
  }
}
