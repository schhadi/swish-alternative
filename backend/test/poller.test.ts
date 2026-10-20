import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { pollInFlightPayments } from "../src/services/payments/poller.js";
import { bearer, createTestApp, linkBank, resetDatabase, signIn, type TestContext } from "./helpers.js";

describe("payment polling fallback", () => {
  let ctx: TestContext;
  let paymentId: string;
  let tlPaymentId: string;
  let samToken: string;

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

  it("leaves fresh payments alone and catches up ones stuck for two minutes", async () => {
    ctx.provider.advance(tlPaymentId, "executed", null, "ob-monzo");
    const fresh = await pollInFlightPayments(ctx.provider, ctx.app.log);
    expect(fresh).toEqual({ checked: 0, changed: 0 });

    const later = new Date(Date.now() + 3 * 60_000);
    const stuck = await pollInFlightPayments(ctx.provider, ctx.app.log, later);
    expect(stuck).toEqual({ checked: 1, changed: 1 });
    const row = await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } });
    expect(row.status).toBe("EXECUTED");
    expect(row.providerId).toBe("ob-monzo");
    expect(row.providerStatus).toBe("executed");
    expect(row.lastPolledAt).not.toBeNull();
  });

  it("does not poll the same payment again within the interval, and stops once it is final", async () => {
    const later = new Date(Date.now() + 3 * 60_000);
    expect(await pollInFlightPayments(ctx.provider, ctx.app.log, later)).toEqual({ checked: 1, changed: 0 });
    expect(await pollInFlightPayments(ctx.provider, ctx.app.log, later)).toEqual({ checked: 0, changed: 0 });

    ctx.provider.advance(tlPaymentId, "failed", "user_canceled");
    const muchLater = new Date(later.getTime() + 2 * 60_000);
    expect(await pollInFlightPayments(ctx.provider, ctx.app.log, muchLater)).toEqual({ checked: 1, changed: 1 });
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } })).status).toBe("CANCELLED");
    expect(await pollInFlightPayments(ctx.provider, ctx.app.log, new Date(muchLater.getTime() + 10 * 60_000))).toEqual({ checked: 0, changed: 0 });
  });

  it("survives a provider that cannot find the payment", async () => {
    await prisma.payment.update({ where: { id: paymentId }, data: { tlPaymentId: "fake_missing" } });
    const later = new Date(Date.now() + 3 * 60_000);
    expect(await pollInFlightPayments(ctx.provider, ctx.app.log, later)).toEqual({ checked: 1, changed: 0 });
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } })).status).toBe("AUTHORIZING");
  });

  it("dev approval page moves a fake payment along and reconciles immediately", async () => {
    const page = await ctx.app.inject({ method: "GET", url: `/dev/authorise/${tlPaymentId}` });
    expect(page.statusCode).toBe(200);
    expect(page.body).toContain("£12.00");
    expect(page.body).not.toContain("87654321");
    const approve = await ctx.app.inject({ method: "POST", url: `/dev/authorise/${tlPaymentId}/approve` });
    expect(approve.statusCode).toBe(303);
    expect(approve.headers.location).toBe("quid://return/payment");
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } })).status).toBe("AUTHORIZED");
    const advance = await ctx.app.inject({ method: "POST", url: `/dev/payments/${tlPaymentId}/advance`, payload: { to: "settled" } });
    expect(advance.statusCode).toBe(200);
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } })).status).toBe("SETTLED");
  });
});
