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
 * Event bodies -> our statuses. Two recorded sandbox payloads in TrueLayer's official signing repository
 * (ruby/test/resources) show the Payments webhook shape: flat, with `type` ("payment_executed", "payment_failed"),
 * `event_version`, `event_id`, `payment_id` and, for failures, `failure_reason`/`failure_stage`; executed events also
 * carry the payer's account identifiers under `payment_source`, which is why a body is never logged. An older
 * `{event_type, event_body}` envelope appears in a payout example, so both are accepted. payment_settled and
 * payment_authorized follow the same naming and stay unverified until docs.truelayer.com is reachable (DECISIONS #59).
 */
export interface WebhookEvent {
  /** Normalised: `type` or `event_type`. */
  event_type: string;
  event_id: string;
  paymentId: string | null;
  failureReason: string | null;
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
  const envelope = typeof event.event_body === "object" && event.event_body !== null ? (event.event_body as Record<string, unknown>) : {};
  const type = typeof event.type === "string" ? event.type : typeof event.event_type === "string" ? event.event_type : null;
  if (!type || typeof event.event_id !== "string") {
    throw new WebhookVerificationError("type and event_id are required");
  }
  const string = (key: string): string | null => {
    if (typeof event[key] === "string") return event[key] as string;
    if (typeof envelope[key] === "string") return envelope[key] as string;
    return null;
  };
  return { event_type: type, event_id: event.event_id, paymentId: string("payment_id"), failureReason: string("failure_reason") };
}

const EVENT_STATUS: Record<string, "authorized" | "executed" | "settled" | "failed"> = {
  payment_authorized: "authorized",
  payment_executed: "executed",
  payment_settled: "settled",
  payment_failed: "failed",
};

export function mapWebhookEvent(event: WebhookEvent): MappedWebhookEvent {
  const providerPaymentId = event.paymentId;
  const raw = EVENT_STATUS[event.event_type];
  if (!raw) {
    return { providerPaymentId, status: null, failureReason: null, providerStatus: event.event_type };
  }
  const mapped = toPaymentStatus({ status: raw, failureReason: event.failureReason });
  return { providerPaymentId, status: mapped.status, failureReason: mapped.failureReason, providerStatus: raw };
}
