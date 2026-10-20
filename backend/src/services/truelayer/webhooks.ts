import type { PaymentStatus } from "@prisma/client";
import * as tlSigning from "truelayer-signing";
import type { HttpMethod } from "truelayer-signing";
import { toPaymentStatus } from "../payments/provider.js";

/**
 * Webhook signature verification (docs/SPEC.md section 5). VERIFIED against TrueLayer's official truelayer-signing
 * webhook example: the Tl-Signature header is a detached JWS whose header carries a `jku`; only TrueLayer's JWKS
 * URLs may be trusted; the X-Tl-Webhook-Timestamp header is part of the signed headers.
 */
export interface WebhookVerifyInput {
  signature: string;
  path: string;
  headers: Record<string, string>;
  body: string;
}

export interface WebhookVerifier {
  /** Resolves when the signature is valid for exactly this path, headers and body; throws otherwise. */
  verify(input: WebhookVerifyInput): Promise<void>;
}

export class WebhookVerificationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WebhookVerificationError";
  }
}

interface Jwks {
  keys: { kid?: string }[];
}

function jkuOf(signature: string): string {
  let jku: string | undefined;
  try {
    jku = tlSigning.extractJku(signature);
  } catch (error) {
    throw new WebhookVerificationError(`unreadable signature: ${error instanceof Error ? error.message : String(error)}`);
  }
  if (!jku) throw new WebhookVerificationError("signature has no jku");
  return jku;
}

function kidOf(signature: string): string {
  try {
    return tlSigning.extractKid(signature);
  } catch (error) {
    throw new WebhookVerificationError(`unreadable signature: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function runVerify(jwks: string, input: WebhookVerifyInput): void {
  try {
    tlSigning.verify({
      jwks,
      signature: input.signature,
      method: "POST" as unknown as HttpMethod,
      path: input.path,
      headers: input.headers,
      body: input.body,
    });
  } catch (error) {
    throw new WebhookVerificationError(error instanceof Error ? error.message : String(error));
  }
}

/** Production verifier: trusts only the configured JWKS URLs, caches the key sets, refetches once on an unknown kid. */
export class TrueLayerWebhookVerifier implements WebhookVerifier {
  private readonly cache = new Map<string, Jwks>();

  constructor(
    private readonly allowedJkus: readonly string[],
    private readonly fetchImpl: typeof fetch = globalThis.fetch,
  ) {}

  async verify(input: WebhookVerifyInput): Promise<void> {
    const jku = jkuOf(input.signature);
    if (!this.allowedJkus.includes(jku)) {
      throw new WebhookVerificationError("signature jku is not a TrueLayer JWKS URL");
    }
    const kid = kidOf(input.signature);
    const jwks = await this.jwks(jku, kid);
    runVerify(JSON.stringify(jwks), input);
  }

  private async jwks(jku: string, kid: string): Promise<Jwks> {
    const cached = this.cache.get(jku);
    if (cached && cached.keys.some((key) => key.kid === kid)) return cached;
    let response: Response;
    try {
      response = await this.fetchImpl(jku);
    } catch (error) {
      throw new WebhookVerificationError(`could not fetch JWKS: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (!response.ok) throw new WebhookVerificationError(`JWKS fetch returned ${response.status}`);
    const fresh = (await response.json()) as Jwks;
    if (!Array.isArray(fresh.keys)) throw new WebhookVerificationError("JWKS response malformed");
    this.cache.set(jku, fresh);
    return fresh;
  }
}

/** Test verifier: a fixed JWKS, optionally without the jku check for events signed by the test key. */
export class StaticJwksWebhookVerifier implements WebhookVerifier {
  constructor(
    private readonly jwksJson: string,
    private readonly allowedJkus: readonly string[] | null = null,
  ) {}

  async verify(input: WebhookVerifyInput): Promise<void> {
    if (this.allowedJkus) {
      const jku = jkuOf(input.signature);
      if (!this.allowedJkus.includes(jku)) throw new WebhookVerificationError("signature jku is not allowed");
    }
    runVerify(this.jwksJson, input);
  }
}

/**
 * Event types -> our statuses. The names follow docs/SPEC.md section 5 (payment_executed, payment_settled,
 * payment_failed) and TrueLayer's "<resource>_<status>" convention seen in their official example (payout_settled);
 * confirm the full list and the event_body field names on docs.truelayer.com before go-live (docs/DECISIONS.md #59).
 */
export interface WebhookEvent {
  event_type: string;
  event_id: string;
  event_body?: Record<string, unknown>;
}

export interface MappedWebhookEvent {
  providerPaymentId: string | null;
  status: PaymentStatus | null;
  failureReason: string | null;
  providerStatus: string;
}

export function parseWebhookEvent(body: string): WebhookEvent {
  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch {
    throw new WebhookVerificationError("body is not JSON");
  }
  if (typeof parsed !== "object" || parsed === null) throw new WebhookVerificationError("body is not an object");
  const event = parsed as Record<string, unknown>;
  if (typeof event.event_type !== "string" || typeof event.event_id !== "string") {
    throw new WebhookVerificationError("event_type and event_id are required");
  }
  return {
    event_type: event.event_type,
    event_id: event.event_id,
    ...(typeof event.event_body === "object" && event.event_body !== null ? { event_body: event.event_body as Record<string, unknown> } : {}),
  };
}

const EVENT_STATUS: Record<string, "authorized" | "executed" | "settled" | "failed"> = {
  payment_authorized: "authorized",
  payment_executed: "executed",
  payment_settled: "settled",
  payment_failed: "failed",
};

export function mapWebhookEvent(event: WebhookEvent): MappedWebhookEvent {
  const body = event.event_body ?? {};
  const providerPaymentId = typeof body.payment_id === "string" ? body.payment_id : null;
  const raw = EVENT_STATUS[event.event_type];
  if (!raw) {
    return { providerPaymentId, status: null, failureReason: null, providerStatus: event.event_type };
  }
  const failureReason = typeof body.failure_reason === "string" ? body.failure_reason : null;
  const mapped = toPaymentStatus({ status: raw, failureReason });
  return { providerPaymentId, status: mapped.status, failureReason: mapped.failureReason, providerStatus: raw };
}
