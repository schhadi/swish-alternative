import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { LIMITS } from "../src/limits.js";
import { ProviderError } from "../src/services/payments/provider.js";
import { bearer, createTestApp, linkBank, resetDatabase, signIn, type TestContext } from "./helpers.js";

describe("POST /payments", () => {
  let ctx: TestContext;
  let samToken: string;
  let samId: string;
  let priyaToken: string;
  let priyaId: string;

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    ({ token: samToken, userId: samId } = await signIn(ctx, "07700 900001"));
    await ctx.app.inject({ method: "PUT", url: "/me", headers: bearer(samToken), payload: { displayName: "Sam Okafor" } });
    ({ token: priyaToken, userId: priyaId } = await signIn(ctx, "07700 900002"));
    await ctx.app.inject({ method: "PUT", url: "/me", headers: bearer(priyaToken), payload: { displayName: "Priya Patel" } });
    await linkBank(ctx, priyaToken, { accountNumber: "87654321", accountHolderName: "Priya Patel", providerId: "ob-starling" });
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  function pay(token: string, payload: Record<string, unknown>) {
    return ctx.app.inject({ method: "POST", url: "/payments", headers: bearer(token), payload });
  }

  it("creates a payment, hands the app the authorisation handles and flags a first-time payee", async () => {
    const response = await pay(samToken, { payeeUserId: priyaId, amountMinor: 1200, reference: "  From   Sam " });
    expect(response.statusCode).toBe(201);
    const body = response.json();
    expect(body.firstTimePayee).toBe(true);
    expect(body.provider).toBe("fake");
    expect(body.resourceToken).toMatch(/^fake_token_/);
    expect(body.authorisationUrl).toContain("/dev/authorise/");
    expect(body.payee).toEqual({ userId: priyaId, displayName: "Priya Patel", accountHolderName: "Priya Patel", copStatus: "MATCH", bankName: "Starling" });
    expect(body.payment).toMatchObject({ id: body.paymentId, status: "AUTHORIZING", amountMinor: 1200, reference: "From Sam", counterparty: { userId: priyaId, displayName: "Priya Patel" } });
    const raw = JSON.stringify(body);
    expect(raw).not.toContain("87654321");
    expect(raw).not.toContain("040004");
    const row = await prisma.payment.findUniqueOrThrow({ where: { id: body.paymentId } });
    expect(row.tlPaymentId).toBe(body.tlPaymentId);
    expect(row.providerStatus).toBe("authorization_required");
  });

  it("is a first-time payee until a payment to them completes", async () => {
    const first = await pay(samToken, { payeeUserId: priyaId, amountMinor: 500, reference: "One" });
    await prisma.payment.update({ where: { id: first.json().paymentId }, data: { status: "EXECUTED" } });
    const second = await pay(samToken, { payeeUserId: priyaId, amountMinor: 500, reference: "Two" });
    expect(second.json().firstTimePayee).toBe(false);
  });

  it("uses the payer's linked bank for preselection and shows it in the feed", async () => {
    await linkBank(ctx, samToken, { providerId: "ob-monzo" });
    const response = await pay(samToken, { payeeUserId: priyaId, amountMinor: 1000, reference: "Lunch" });
    expect(response.json().payment.bankName).toBe("Monzo");
    const feed = await ctx.app.inject({ method: "GET", url: "/payments?role=sent", headers: bearer(samToken) });
    expect(feed.json().payments[0].bankName).toBe("Monzo");
    const received = await ctx.app.inject({ method: "GET", url: "/payments?role=received", headers: bearer(priyaToken) });
    expect(received.json().payments[0]).toMatchObject({ status: "AUTHORIZING", counterparty: { userId: samId, displayName: "Sam Okafor" } });
  });

  it("enforces the per-payment limit", async () => {
    const response = await pay(samToken, { payeeUserId: priyaId, amountMinor: LIMITS.perPaymentMinor + 1, reference: "Too much" });
    expect(response.statusCode).toBe(400);
    expect(response.json()).toMatchObject({ error: "limit_per_payment", details: { limitMinor: LIMITS.perPaymentMinor } });
    expect(await prisma.payment.count()).toBe(0);
  });

  it("enforces the rolling 24h limit, counting payments still in flight", async () => {
    expect((await pay(samToken, { payeeUserId: priyaId, amountMinor: 25000, reference: "A" })).statusCode).toBe(201);
    expect((await pay(samToken, { payeeUserId: priyaId, amountMinor: 25000, reference: "B" })).statusCode).toBe(201);
    const blocked = await pay(samToken, { payeeUserId: priyaId, amountMinor: 100, reference: "C" });
    expect(blocked.statusCode).toBe(400);
    expect(blocked.json()).toMatchObject({ error: "limit_24h", details: { limitMinor: LIMITS.rolling24hMinor, remainingMinor: 0 } });
    // A failed payment no longer counts.
    await prisma.payment.updateMany({ where: { payerUserId: samId, reference: "B" }, data: { status: "FAILED" } });
    expect((await pay(samToken, { payeeUserId: priyaId, amountMinor: 100, reference: "C" })).statusCode).toBe(201);
  });

  it("enforces the rolling 30d limit using older payments", async () => {
    const tenDaysAgo = new Date(Date.now() - 10 * 24 * 60 * 60 * 1000);
    for (let i = 0; i < 8; i += 1) {
      await prisma.payment.create({ data: { payerUserId: samId, payeeUserId: priyaId, amountMinor: 24000, reference: "Old", status: "SETTLED", createdAt: tenDaysAgo } });
    }
    const blocked = await pay(samToken, { payeeUserId: priyaId, amountMinor: 10000, reference: "New" });
    expect(blocked.statusCode).toBe(400);
    expect(blocked.json()).toMatchObject({ error: "limit_30d", details: { remainingMinor: LIMITS.rolling30dMinor - 8 * 24000 } });
    expect((await pay(samToken, { payeeUserId: priyaId, amountMinor: 8000, reference: "New" })).statusCode).toBe(201);
  });

  it("never lets parallel requests exceed a window together", async () => {
    const responses = await Promise.all(Array.from({ length: 6 }, (_, i) => pay(samToken, { payeeUserId: priyaId, amountMinor: 20000, reference: `P${i}` })));
    const created = responses.filter((r) => r.statusCode === 201).length;
    expect(created).toBe(2);
    expect(responses.filter((r) => r.statusCode === 400).every((r) => r.json().error === "limit_24h")).toBe(true);
  });

  it("refuses payees who cannot receive", async () => {
    const { token: tomToken, userId: tomId } = await signIn(ctx, "07700 900003");
    await ctx.app.inject({ method: "PUT", url: "/me", headers: bearer(tomToken), payload: { displayName: "Tom Whitfield" } });
    const noBank = await pay(samToken, { payeeUserId: tomId, amountMinor: 100, reference: "Hi" });
    expect(noBank.statusCode).toBe(400);
    expect(noBank.json().error).toBe("payee_not_payable");

    const self = await pay(samToken, { payeeUserId: samId, amountMinor: 100, reference: "Me" });
    expect(self.json().error).toBe("self_payment");

    const unknown = await pay(samToken, { payeeUserId: "nobody", amountMinor: 100, reference: "Hi" });
    expect(unknown.statusCode).toBe(404);

    // Priya changes her account: cooling-off starts.
    await linkBank(ctx, priyaToken, { sortCode: "20-00-00", accountNumber: "11112222", accountHolderName: "Priya Patel" });
    const cooling = await pay(samToken, { payeeUserId: priyaId, amountMinor: 100, reference: "Hi" });
    expect(cooling.statusCode).toBe(400);
    expect(cooling.json()).toMatchObject({ error: "payee_cooling_off", details: { coolingOffUntil: expect.any(String) } });
    expect(await prisma.payment.count()).toBe(0);
  });

  it("validates the reference and the amount", async () => {
    for (const reference of ["", "This reference is far too long", "Bad £ chars", "émoji ✓"]) {
      const response = await pay(samToken, { payeeUserId: priyaId, amountMinor: 100, reference });
      expect(response.statusCode).toBe(400);
      expect(["invalid_reference", "validation_error"]).toContain(response.json().error);
    }
    expect((await pay(samToken, { payeeUserId: priyaId, amountMinor: 0, reference: "Zero" })).statusCode).toBe(400);
    expect((await pay(samToken, { payeeUserId: priyaId, amountMinor: 12.5, reference: "Pence" })).statusCode).toBe(400);
    expect((await pay(samToken, { payeeUserId: priyaId, amountMinor: 100, reference: "Ok & fine./-" })).statusCode).toBe(201);
  });

  it("marks the payment FAILED and answers 502 when the provider refuses", async () => {
    ctx.provider.failNextCreate = new ProviderError("down", 503, "service_unavailable");
    const response = await pay(samToken, { payeeUserId: priyaId, amountMinor: 100, reference: "Hi" });
    expect(response.statusCode).toBe(502);
    expect(response.json().error).toBe("payment_provider_unavailable");
    const row = await prisma.payment.findFirstOrThrow({ where: { payerUserId: samId } });
    expect(row.status).toBe("FAILED");
    expect(row.failureReason).toBe("provider_error");
    expect(row.tlPaymentId).toBeNull();
    // and it no longer counts against the window
    expect((await pay(samToken, { payeeUserId: priyaId, amountMinor: 25000, reference: "Again" })).statusCode).toBe(201);
  });

  it("defers collections and requests to later phases", async () => {
    const response = await pay(samToken, { collectionId: "col_1", amountMinor: 100, reference: "Hi" });
    expect(response.statusCode).toBe(400);
    expect(response.json().error).toBe("not_supported_yet");
  });

  it("requires auth", async () => {
    const response = await ctx.app.inject({ method: "POST", url: "/payments", payload: { payeeUserId: priyaId, amountMinor: 100, reference: "Hi" } });
    expect(response.statusCode).toBe(401);
  });
});
