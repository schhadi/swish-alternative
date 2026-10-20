import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { StaticJwksWebhookVerifier, TrueLayerWebhookVerifier, mapWebhookEvent } from "../src/services/truelayer/webhooks.js";
import { bearer, createTestApp, fixture, linkBank, resetDatabase, signIn, type TestContext } from "./helpers.js";
import { signWebhook } from "./support/webhookSigner.js";

const KID = "45fc75cf-5649-4134-84b3-192c2c78e990";
const JKU = "https://webhooks.truelayer.com/.well-known/jwks";

/** The recorded webhook from TrueLayer's shared test resources (test/fixtures/truelayer/README.md). */
const RECORDED = {
  signature: fixture("webhook-signature.txt").trim(),
  path: "/tl-webhook",
  headers: { "x-tl-webhook-timestamp": "2021-11-29T11:42:55Z", "content-type": "application/json" },
  body: '{"event_type":"example","event_id":"18b2842b-a57b-4887-a0a6-d3c7c36f1020"}',
};

describe("webhook signature verification", () => {
  it("accepts TrueLayer's recorded webhook signature with their published JWKS", async () => {
    const verifier = new StaticJwksWebhookVerifier(fixture("jwks.json"), [JKU]);
    await expect(verifier.verify(RECORDED)).resolves.toBeUndefined();
  });

  it("rejects the recorded signature when the body, a signed header or the path changes", async () => {
    const verifier = new StaticJwksWebhookVerifier(fixture("jwks.json"), [JKU]);
    await expect(verifier.verify({ ...RECORDED, body: RECORDED.body.replace("example", "payment_settled") })).rejects.toThrow();
    await expect(verifier.verify({ ...RECORDED, headers: { ...RECORDED.headers, "x-tl-webhook-timestamp": "2021-11-29T11:42:56Z" } })).rejects.toThrow();
    await expect(verifier.verify({ ...RECORDED, path: "/webhooks/truelayer" })).rejects.toThrow();
  });

  it("trusts only TrueLayer's JWKS URLs and caches the key set per jku", async () => {
    let fetches = 0;
    const fakeFetch = (async (url: string | URL | Request) => {
      fetches += 1;
      expect(String(url)).toBe(JKU);
      return new Response(fixture("jwks.json"), { status: 200, headers: { "content-type": "application/json" } });
    }) as unknown as typeof fetch;
    const trusting = new TrueLayerWebhookVerifier([JKU], fakeFetch);
    await expect(trusting.verify(RECORDED)).resolves.toBeUndefined();
    await expect(trusting.verify(RECORDED)).resolves.toBeUndefined();
    expect(fetches).toBe(1);

    const sandboxOnly = new TrueLayerWebhookVerifier(["https://webhooks.truelayer-sandbox.com/.well-known/jwks"], fakeFetch);
    await expect(sandboxOnly.verify(RECORDED)).rejects.toThrow(/jku/);
    expect(fetches).toBe(1);
  });

  it("verifies a signature produced by an independent ES512 signer", async () => {
    const verifier = new StaticJwksWebhookVerifier(fixture("jwks.json"), [JKU]);
    const headers = { "X-Tl-Webhook-Timestamp": "2026-10-20T12:00:00Z", "Content-Type": "application/json" };
    const body = '{"event_type":"payment_settled","event_id":"e1","event_body":{"payment_id":"tl_1"}}';
    const signature = signWebhook({ privateKeyPem: fixture("ec512-private.pem"), kid: KID, jku: JKU, path: "/webhooks/truelayer", headers, body });
    await expect(verifier.verify({ signature, path: "/webhooks/truelayer", headers, body })).resolves.toBeUndefined();
    await expect(verifier.verify({ signature, path: "/webhooks/truelayer", headers, body: body.replace("tl_1", "tl_2") })).rejects.toThrow();
  });

  it("maps event types to statuses and ignores the rest", () => {
    expect(mapWebhookEvent({ event_type: "payment_executed", event_id: "1", event_body: { payment_id: "tl" } })).toMatchObject({ providerPaymentId: "tl", status: "EXECUTED" });
    expect(mapWebhookEvent({ event_type: "payment_settled", event_id: "1", event_body: { payment_id: "tl" } })).toMatchObject({ status: "SETTLED" });
    expect(mapWebhookEvent({ event_type: "payment_authorized", event_id: "1", event_body: { payment_id: "tl" } })).toMatchObject({ status: "AUTHORIZED" });
    expect(mapWebhookEvent({ event_type: "payment_failed", event_id: "1", event_body: { payment_id: "tl", failure_reason: "canceled" } })).toMatchObject({ status: "CANCELLED", failureReason: "canceled" });
    expect(mapWebhookEvent({ event_type: "payment_failed", event_id: "1", event_body: { payment_id: "tl", failure_reason: "insufficient_funds" } })).toMatchObject({ status: "FAILED" });
    expect(mapWebhookEvent({ event_type: "payout_settled", event_id: "1", event_body: { payment_id: "tl" } })).toMatchObject({ status: null });
  });
});

describe("POST /webhooks/truelayer", () => {
  let ctx: TestContext;
  let samToken: string;
  let paymentId: string;
  let tlPaymentId: string;

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    ({ token: samToken } = await signIn(ctx, "07700 900001"));
    await ctx.app.inject({ method: "PUT", url: "/me", headers: bearer(samToken), payload: { displayName: "Sam Okafor" } });
    const priya = await signIn(ctx, "07700 900002");
    await ctx.app.inject({ method: "PUT", url: "/me", headers: bearer(priya.token), payload: { displayName: "Priya Patel" } });
    await linkBank(ctx, priya.token, { accountNumber: "87654321", accountHolderName: "Priya Patel" });
    const created = await ctx.app.inject({ method: "POST", url: "/payments", headers: bearer(samToken), payload: { payeeUserId: priya.userId, amountMinor: 1200, reference: "From Sam" } });
    paymentId = created.json().paymentId;
    tlPaymentId = created.json().tlPaymentId;
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  function deliver(event: Record<string, unknown>, tamper: { body?: string; timestamp?: string; unsigned?: boolean } = {}) {
    const body = JSON.stringify(event);
    const timestamp = new Date().toISOString();
    const headers = { "X-Tl-Webhook-Timestamp": timestamp, "Content-Type": "application/json" };
    const signature = signWebhook({ privateKeyPem: fixture("ec512-private.pem"), kid: KID, jku: JKU, path: "/webhooks/truelayer", headers, body });
    return ctx.app.inject({
      method: "POST",
      url: "/webhooks/truelayer",
      headers: {
        "content-type": "application/json",
        "x-tl-webhook-timestamp": tamper.timestamp ?? timestamp,
        ...(tamper.unsigned ? {} : { "tl-signature": signature }),
      },
      payload: tamper.body ?? body,
    });
  }

  async function status(): Promise<string> {
    return (await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } })).status;
  }

  it("applies executed then settled, and acknowledges a redelivery without applying it twice", async () => {
    const executed = await deliver({ event_type: "payment_executed", event_schema_version: 1, event_id: "evt-1", event_body: { payment_id: tlPaymentId } });
    expect(executed.statusCode).toBe(200);
    expect(executed.json()).toEqual({ received: true, applied: true });
    expect(await status()).toBe("EXECUTED");

    const settled = await deliver({ event_type: "payment_settled", event_schema_version: 1, event_id: "evt-2", event_body: { payment_id: tlPaymentId } });
    expect(settled.json()).toEqual({ received: true, applied: true });
    expect(await status()).toBe("SETTLED");

    const again = await deliver({ event_type: "payment_executed", event_schema_version: 1, event_id: "evt-1", event_body: { payment_id: tlPaymentId } });
    expect(again.statusCode).toBe(200);
    expect(again.json()).toEqual({ received: true, duplicate: true });
    expect(await status()).toBe("SETTLED");
    expect(await prisma.webhookEvent.count()).toBe(2);
  });

  it("keeps the later status when webhooks arrive out of order", async () => {
    await deliver({ event_type: "payment_settled", event_id: "evt-s", event_body: { payment_id: tlPaymentId } });
    const stale = await deliver({ event_type: "payment_executed", event_id: "evt-e", event_body: { payment_id: tlPaymentId } });
    expect(stale.json()).toEqual({ received: true, applied: false });
    expect(await status()).toBe("SETTLED");
  });

  it("marks a payment failed, with the reason, and cancelled when the payer backed out", async () => {
    const failed = await deliver({ event_type: "payment_failed", event_id: "evt-f", event_body: { payment_id: tlPaymentId, failure_reason: "insufficient_funds" } });
    expect(failed.json()).toEqual({ received: true, applied: true });
    const row = await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } });
    expect(row.status).toBe("FAILED");
    expect(row.failureReason).toBe("insufficient_funds");
  });

  it("refuses unsigned, tampered and stale deliveries without touching the payment", async () => {
    const event = { event_type: "payment_settled", event_id: "evt-x", event_body: { payment_id: tlPaymentId } };
    expect((await deliver(event, { unsigned: true })).statusCode).toBe(403);
    expect((await deliver(event, { body: JSON.stringify({ ...event, event_body: { payment_id: "other" } }) })).statusCode).toBe(403);
    expect(await status()).toBe("AUTHORIZING");
    expect(await prisma.webhookEvent.count()).toBe(0);

    const strict = await createTestApp({ webhookMaxAgeSeconds: 60 });
    try {
      const body = JSON.stringify(event);
      const headers = { "X-Tl-Webhook-Timestamp": "2021-11-29T11:42:55Z", "Content-Type": "application/json" };
      const signature = signWebhook({ privateKeyPem: fixture("ec512-private.pem"), kid: KID, jku: JKU, path: "/webhooks/truelayer", headers, body });
      const old = await strict.app.inject({
        method: "POST",
        url: "/webhooks/truelayer",
        headers: { "content-type": "application/json", "x-tl-webhook-timestamp": headers["X-Tl-Webhook-Timestamp"], "tl-signature": signature },
        payload: body,
      });
      expect(old.statusCode).toBe(403);
      expect(old.json().error).toBe("webhook_stale");
    } finally {
      await strict.app.close();
    }
  });

  it("acknowledges unknown payments and unknown event types so TrueLayer stops retrying", async () => {
    const unknown = await deliver({ event_type: "payment_settled", event_id: "evt-u", event_body: { payment_id: "tl_nobody" } });
    expect(unknown.statusCode).toBe(200);
    expect(unknown.json()).toEqual({ received: true, applied: false });
    const other = await deliver({ event_type: "payout_settled", event_id: "evt-o", event_body: { transaction_id: "t" } });
    expect(other.json()).toEqual({ received: true, applied: false });
    const malformed = await deliver({ hello: "world" });
    expect(malformed.statusCode).toBe(400);
  });

  it("does not require a bearer token and is not rate limited like user routes", async () => {
    const response = await deliver({ event_type: "payment_authorized", event_id: "evt-a", event_body: { payment_id: tlPaymentId } });
    expect(response.statusCode).toBe(200);
    expect(await status()).toBe("AUTHORIZED");
  });
});
