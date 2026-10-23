import { describe, expect, it } from "vitest";
import * as tlSigning from "truelayer-signing";
import type { HttpMethod } from "truelayer-signing";
import { ProviderError } from "../src/services/payments/provider.js";
import { TrueLayerClient } from "../src/services/truelayer/client.js";
import { fixture } from "./helpers.js";

const KID = "45fc75cf-5649-4134-84b3-192c2c78e990";

interface Captured {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string | null;
}

/** A fetch that records every call and answers from a script. */
function scriptedFetch(responses: Array<{ status: number; body: unknown }>) {
  const calls: Captured[] = [];
  const impl = (async (url: string | URL | Request, init?: RequestInit) => {
    const headers: Record<string, string> = {};
    for (const [name, value] of Object.entries((init?.headers ?? {}) as Record<string, string>)) headers[name.toLowerCase()] = value;
    calls.push({ url: String(url), method: init?.method ?? "GET", headers, body: typeof init?.body === "string" ? init.body : null });
    const next = responses.shift();
    if (!next) throw new Error("unexpected fetch");
    return new Response(JSON.stringify(next.body), { status: next.status, headers: { "content-type": "application/json" } });
  }) as unknown as typeof fetch;
  return { impl, calls };
}

function client(fetchImpl: typeof fetch, now = () => 1_000_000) {
  return new TrueLayerClient({
    apiBaseUrl: "https://api.truelayer-sandbox.com",
    authBaseUrl: "https://auth.truelayer-sandbox.com",
    hppBaseUrl: "https://payment.truelayer-sandbox.com",
    clientId: "sandbox-quid",
    clientSecret: "secret",
    kid: KID,
    privateKeyPem: fixture("ec512-private.pem"),
    fetch: fetchImpl,
    now,
  });
}

describe("TrueLayerClient", () => {
  it("the verify oracle accepts TrueLayer's recorded request signature and rejects a tampered body", () => {
    // Recorded request signature from TrueLayer's shared test resources (test/fixtures/truelayer/README.md).
    const recorded = {
      publicKeyPem: fixture("ec512-public.pem"),
      signature: fixture("tl-signature.txt").trim(),
      method: "POST" as unknown as HttpMethod,
      path: "/merchant_accounts/a61acaef-ee05-4077-92f3-25543a11bd8d/sweeping",
      headers: { "Idempotency-Key": "idemp-2076717c-9005-4811-a321-9e0787fa0382" },
      body: '{"currency":"GBP","max_amount_in_minor":5000000,"name":"Foo???"}',
    };
    expect(() => tlSigning.verify(recorded)).not.toThrow();
    expect(() => tlSigning.verify({ ...recorded, body: recorded.body.replace("5000000", "5000001") })).toThrow();
    expect(() => tlSigning.verify({ ...recorded, headers: { "Idempotency-Key": "idemp-other" } })).toThrow();
  });

  it("fetches a token, signs the create request with our id as the Idempotency-Key and builds the hosted page URL", async () => {
    const { impl, calls } = scriptedFetch([
      { status: 200, body: { access_token: "tok", expires_in: 3600 } },
      { status: 201, body: { id: "tl_123", resource_token: "rt_456", status: "authorization_required" } },
    ]);
    const created = await client(impl).createPayment({
      paymentId: "our-id",
      amountMinor: 1200,
      currency: "GBP",
      reference: "From Sam",
      beneficiary: { accountHolderName: "Priya Patel", sortCode: "040004", accountNumber: "87654321" },
      payer: { id: "u1", name: "Sam Okafor", phoneE164: "+447700900001" },
      providerSelection: { type: "preselected", providerId: "ob-monzo" },
      returnUri: "quid://return/payment",
    });
    expect(created).toEqual({
      providerPaymentId: "tl_123",
      resourceToken: "rt_456",
      authorisationUrl: "https://payment.truelayer-sandbox.com/payments#payment_id=tl_123&resource_token=rt_456&return_uri=quid%3A%2F%2Freturn%2Fpayment",
      status: "authorization_required",
    });

    const [token, create] = calls;
    expect(token).toMatchObject({ url: "https://auth.truelayer-sandbox.com/connect/token", method: "POST" });
    expect(token?.body).toContain("grant_type=client_credentials");
    expect(token?.body).toContain("scope=payments");

    expect(create).toMatchObject({ url: "https://api.truelayer-sandbox.com/v3/payments", method: "POST" });
    expect(create?.headers.authorization).toBe("Bearer tok");
    expect(create?.headers["idempotency-key"]).toBe("our-id");
    const body = JSON.parse(create?.body ?? "{}");
    expect(body).toEqual({
      amount_in_minor: 1200,
      currency: "GBP",
      payment_method: {
        type: "bank_transfer",
        provider_selection: { type: "preselected", provider_id: "ob-monzo" },
        beneficiary: {
          type: "external_account",
          account_holder_name: "Priya Patel",
          account_identifier: { type: "sort_code_account_number", sort_code: "040004", account_number: "87654321" },
          reference: "From Sam",
        },
      },
      user: { id: "u1", name: "Sam Okafor", phone_number: "+447700900001" },
    });
    // The signature verifies with TrueLayer's own library against the matching public key, for exactly this request.
    expect(() =>
      tlSigning.verify({
        publicKeyPem: fixture("ec512-public.pem"),
        signature: create?.headers["tl-signature"] ?? "",
        method: "POST" as unknown as HttpMethod,
        path: "/v3/payments",
        headers: { "Idempotency-Key": "our-id" },
        body: create?.body ?? "",
      }),
    ).not.toThrow();
    expect(() =>
      tlSigning.verify({
        publicKeyPem: fixture("ec512-public.pem"),
        signature: create?.headers["tl-signature"] ?? "",
        method: "POST" as unknown as HttpMethod,
        path: "/v3/payments",
        headers: { "Idempotency-Key": "someone-elses-id" },
        body: create?.body ?? "",
      }),
    ).toThrow();
  });

  it("reuses the token until it is about to expire and reads payment state", async () => {
    let clock = 0;
    const { impl, calls } = scriptedFetch([
      { status: 200, body: { access_token: "tok1", expires_in: 100 } },
      { status: 200, body: { id: "tl_1", status: "executed" } },
      { status: 200, body: { id: "tl_1", status: "failed", failure_reason: "canceled", payment_method: { provider_selection: { provider_id: "ob-monzo" } } } },
      { status: 200, body: { access_token: "tok2", expires_in: 100 } },
      { status: 200, body: { id: "tl_1", status: "settled" } },
    ]);
    const tl = client(impl, () => clock);
    expect(await tl.getPayment("tl_1")).toEqual({ status: "executed", failureReason: null, providerId: null });
    expect(await tl.getPayment("tl_1")).toEqual({ status: "failed", failureReason: "canceled", providerId: "ob-monzo" });
    clock = 50_000; // 50s in: within 60s of expiry, so a new token is fetched
    expect(await tl.getPayment("tl_1")).toEqual({ status: "settled", failureReason: null, providerId: null });
    expect(calls.filter((c) => c.url.endsWith("/connect/token"))).toHaveLength(2);
    expect(calls[1]?.url).toBe("https://api.truelayer-sandbox.com/v3/payments/tl_1");
  });

  it("turns HTTP failures into ProviderError without leaking bodies", async () => {
    const { impl } = scriptedFetch([
      { status: 200, body: { access_token: "tok", expires_in: 3600 } },
      { status: 400, body: { type: "https://docs.truelayer.com/errors#invalid_parameters", title: "Invalid parameters" } },
    ]);
    await expect(client(impl).getPayment("tl_bad")).rejects.toMatchObject({ name: "ProviderError", httpStatus: 400, providerCode: "https://docs.truelayer.com/errors#invalid_parameters" });

    const { impl: rejectToken } = scriptedFetch([{ status: 401, body: { error: "invalid_client" } }]);
    await expect(client(rejectToken).getPayment("tl")).rejects.toBeInstanceOf(ProviderError);

    const { impl: weird } = scriptedFetch([
      { status: 200, body: { access_token: "tok", expires_in: 3600 } },
      { status: 200, body: { id: "tl", status: "something_new" } },
    ]);
    await expect(client(weird).getPayment("tl")).rejects.toMatchObject({ providerCode: "unknown_status" });
  });

  it("cancels with a signed POST to the payment's cancel action and accepts an empty 202", async () => {
    const { impl, calls } = scriptedFetch([
      { status: 200, body: { access_token: "tok", expires_in: 3600 } },
      { status: 202, body: undefined },
      { status: 400, body: { type: "https://docs.truelayer.com/errors#payment_not_cancellable" } },
    ]);
    const tl = client(impl);
    await expect(tl.cancelPayment("tl_9")).resolves.toBeUndefined();
    const cancel = calls[1];
    expect(cancel).toMatchObject({ url: "https://api.truelayer-sandbox.com/v3/payments/tl_9/actions/cancel", method: "POST", body: "{}" });
    const key = cancel?.headers["idempotency-key"] ?? "";
    expect(key).not.toBe("");
    expect(() =>
      tlSigning.verify({
        publicKeyPem: fixture("ec512-public.pem"),
        signature: cancel?.headers["tl-signature"] ?? "",
        method: "POST" as unknown as HttpMethod,
        path: "/v3/payments/tl_9/actions/cancel",
        headers: { "Idempotency-Key": key },
        body: "{}",
      }),
    ).not.toThrow();
    // Once the payment is past the point of cancelling, the 4xx comes back as a ProviderError.
    await expect(tl.cancelPayment("tl_9")).rejects.toMatchObject({ name: "ProviderError", httpStatus: 400 });
    expect(calls[2]?.headers["idempotency-key"]).not.toBe(key);
  });
});
