import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { LIMITS } from "../src/limits.js";
import { pollInFlightPayments } from "../src/services/payments/poller.js";
import { applyTransition } from "../src/services/payments/stateMachine.js";
import { expireStaleRequests } from "../src/services/requests/service.js";
import { bearer, createTestApp, registerUser, resetDatabase, silentLog, type TestContext } from "./helpers.js";

const DAY_MS = 24 * 60 * 60 * 1000;

describe("payment requests", () => {
  let ctx: TestContext;
  let sam: { token: string; userId: string };
  let priya: { token: string; userId: string };
  let tom: { token: string; userId: string };

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    // Sam asks; Priya and Tom are asked. Only the requester needs a bank account to ask.
    sam = await registerUser(ctx, "07700 900001", "Sam Okafor", { accountNumber: "11112222", providerId: "ob-monzo" });
    priya = await registerUser(ctx, "07700 900002", "Priya Patel", { accountNumber: "87654321", providerId: "ob-starling" });
    tom = await registerUser(ctx, "07700 900003", "Tom Whitfield", null);
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  function ask(token: string, payload: Record<string, unknown>) {
    return ctx.app.inject({ method: "POST", url: "/requests", headers: bearer(token), payload });
  }

  function post(token: string, url: string, payload?: Record<string, unknown>) {
    return ctx.app.inject({ method: "POST", url, headers: bearer(token), ...(payload ? { payload } : {}) });
  }

  function get(token: string, url: string) {
    return ctx.app.inject({ method: "GET", url, headers: bearer(token) });
  }

  async function samAsksPriya(amountMinor = 1800) {
    const response = await ask(sam.token, { payerUserId: priya.userId, amountMinor, reference: "Pizza night", note: "  Friday,  four ways " });
    expect(response.statusCode).toBe(201);
    return response.json();
  }

  it("creates a pending request that both sides can see, expiring in 14 days", async () => {
    const before = Date.now();
    const request = await samAsksPriya();
    expect(request).toMatchObject({
      requesterUserId: sam.userId,
      payerUserId: priya.userId,
      amountMinor: 1800,
      reference: "Pizza night",
      note: "Friday, four ways",
      status: "PENDING",
      paymentId: null,
      requester: { userId: sam.userId, displayName: "Sam Okafor" },
      payer: { userId: priya.userId, displayName: "Priya Patel" },
      splitId: null,
      splitTitle: null,
      remindCount: 0,
      nextReminderAt: null,
    });
    const expiry = Date.parse(request.expiresAt) - before;
    expect(expiry).toBeGreaterThanOrEqual(LIMITS.requestExpiryDays * DAY_MS - 1000);
    expect(expiry).toBeLessThanOrEqual(LIMITS.requestExpiryDays * DAY_MS + 5000);

    const incoming = (await get(priya.token, "/requests?role=incoming&status=pending")).json().requests;
    expect(incoming.map((row: { id: string }) => row.id)).toEqual([request.id]);
    const outgoing = (await get(sam.token, "/requests?role=outgoing")).json().requests;
    expect(outgoing.map((row: { id: string }) => row.id)).toEqual([request.id]);
    expect((await get(sam.token, "/requests?role=incoming")).json().requests).toEqual([]);
    expect((await get(priya.token, `/requests/${request.id}`)).statusCode).toBe(200);
    expect((await get(tom.token, `/requests/${request.id}`)).statusCode).toBe(404);
  });

  it("refuses requests nobody could pay", async () => {
    expect((await ask(sam.token, { payerUserId: sam.userId, amountMinor: 500, reference: "Me" })).json().error).toBe("self_request");
    expect((await ask(sam.token, { payerUserId: "00000000-0000-4000-8000-000000000000", amountMinor: 500, reference: "Who" })).statusCode).toBe(404);
    const over = await ask(sam.token, { payerUserId: priya.userId, amountMinor: LIMITS.perPaymentMinor + 1, reference: "Rent" });
    expect(over.json()).toMatchObject({ error: "request_over_limit", details: { limitMinor: LIMITS.perPaymentMinor } });
    expect((await ask(sam.token, { payerUserId: priya.userId, amountMinor: 0, reference: "Nothing" })).json().error).toBe("invalid_amount");
    expect((await ask(sam.token, { payerUserId: priya.userId, amountMinor: 500, reference: "Pizza 🍕" })).json().error).toBe("invalid_reference");
    expect((await ask(sam.token, { payerUserId: priya.userId, amountMinor: 500, reference: "Pizza", note: "x".repeat(141) })).json().error).toBe("invalid_note");
    // Tom has no bank account, so nobody could pay him.
    expect((await ask(tom.token, { payerUserId: priya.userId, amountMinor: 500, reference: "Lunch" })).json().error).toBe("requester_not_payable");
    expect(await prisma.paymentRequest.count()).toBe(0);
  });

  it("refuses requests from someone in their bank-change cooling-off", async () => {
    await prisma.bankAccount.updateMany({ where: { userId: sam.userId }, data: { changedAt: new Date() } });
    const response = await ask(sam.token, { payerUserId: priya.userId, amountMinor: 500, reference: "Lunch" });
    expect(response.statusCode).toBe(400);
    expect(response.json()).toMatchObject({ error: "requester_cooling_off", details: { coolingOffUntil: expect.any(String) } });
    expect(response.json().message).not.toMatch(/T\d\d:/);
  });

  it("lets only the payer decline, once", async () => {
    const request = await samAsksPriya();
    expect((await post(sam.token, `/requests/${request.id}/decline`)).statusCode).toBe(404);
    expect((await post(tom.token, `/requests/${request.id}/decline`)).statusCode).toBe(404);
    const declined = await post(priya.token, `/requests/${request.id}/decline`);
    expect(declined.statusCode).toBe(200);
    expect(declined.json()).toMatchObject({ status: "DECLINED", declinedAt: expect.any(String) });
    const again = await post(priya.token, `/requests/${request.id}/decline`);
    expect(again.statusCode).toBe(409);
    expect(again.json()).toMatchObject({ error: "request_not_pending", details: { status: "DECLINED" } });
    expect((await get(priya.token, "/requests?role=incoming&status=pending")).json().requests).toEqual([]);
    expect((await get(priya.token, "/requests?role=incoming")).json().requests).toHaveLength(1);
  });

  it("rate-limits reminders to once per 24 hours per request", async () => {
    const request = await samAsksPriya();
    expect((await post(priya.token, `/requests/${request.id}/remind`)).statusCode).toBe(404);
    const first = await post(sam.token, `/requests/${request.id}/remind`);
    expect(first.statusCode).toBe(200);
    expect(first.json()).toMatchObject({ remindCount: 1, lastRemindedAt: expect.any(String) });
    expect(Date.parse(first.json().nextReminderAt) - Date.parse(first.json().lastRemindedAt)).toBe(LIMITS.reminderMinIntervalHours * 60 * 60 * 1000);

    const tooSoon = await post(sam.token, `/requests/${request.id}/remind`);
    expect(tooSoon.statusCode).toBe(429);
    expect(tooSoon.json()).toMatchObject({ error: "remind_too_soon", details: { nextReminderAt: first.json().nextReminderAt } });
    expect((await prisma.paymentRequest.findUniqueOrThrow({ where: { id: request.id } })).remindCount).toBe(1);

    // A day later the next nudge goes through.
    await prisma.paymentRequest.update({ where: { id: request.id }, data: { lastRemindedAt: new Date(Date.now() - DAY_MS - 1000) } });
    const later = await post(sam.token, `/requests/${request.id}/remind`);
    expect(later.statusCode).toBe(200);
    expect(later.json().remindCount).toBe(2);

    await post(priya.token, `/requests/${request.id}/decline`);
    await prisma.paymentRequest.update({ where: { id: request.id }, data: { lastRemindedAt: null } });
    expect((await post(sam.token, `/requests/${request.id}/remind`)).json()).toMatchObject({ error: "request_not_pending", details: { status: "DECLINED" } });
  });

  it("sends one reminder when two arrive at once", async () => {
    const request = await samAsksPriya();
    const results = await Promise.all([post(sam.token, `/requests/${request.id}/remind`), post(sam.token, `/requests/${request.id}/remind`)]);
    expect(results.map((result) => result.statusCode).sort()).toEqual([200, 429]);
    expect((await prisma.paymentRequest.findUniqueOrThrow({ where: { id: request.id } })).remindCount).toBe(1);
  });

  it("treats an open request past its expiry as expired everywhere, and the sweep writes it", async () => {
    const request = await samAsksPriya();
    await prisma.paymentRequest.update({ where: { id: request.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
    expect((await get(priya.token, `/requests/${request.id}`)).json().status).toBe("EXPIRED");
    expect((await get(priya.token, "/requests?role=incoming&status=pending")).json().requests).toEqual([]);
    expect((await post(priya.token, `/requests/${request.id}/decline`)).json()).toMatchObject({ error: "request_not_pending", details: { status: "EXPIRED" } });
    expect((await post(sam.token, `/requests/${request.id}/remind`)).json()).toMatchObject({ error: "request_not_pending", details: { status: "EXPIRED" } });
    const pay = await post(priya.token, "/payments", { requestId: request.id });
    expect(pay.statusCode).toBe(409);
    expect(await expireStaleRequests()).toBe(1);
    expect((await prisma.paymentRequest.findUniqueOrThrow({ where: { id: request.id } })).status).toBe("EXPIRED");
  });

  describe("paying a request", () => {
    it("pays the requester the requested amount and reference, and marks the request paid once the bank executes", async () => {
      const request = await samAsksPriya();
      const created = await post(priya.token, "/payments", { requestId: request.id, amountMinor: 1800 });
      expect(created.statusCode).toBe(201);
      const body = created.json();
      expect(body.payee).toMatchObject({ userId: sam.userId, displayName: "Sam Okafor" });
      expect(body.payment).toMatchObject({ requestId: request.id, amountMinor: 1800, reference: "Pizza night", payeeUserId: sam.userId });
      expect((await get(priya.token, `/requests/${request.id}`)).json().status).toBe("PENDING");

      const advanced = await ctx.app.inject({ method: "POST", url: `/dev/payments/${body.tlPaymentId}/advance`, payload: { to: "executed" } });
      expect(advanced.statusCode).toBe(200);
      const paid = (await get(sam.token, `/requests/${request.id}`)).json();
      expect(paid).toMatchObject({ status: "PAID", paymentId: body.paymentId, paidAt: expect.any(String) });

      const again = await post(priya.token, "/payments", { requestId: request.id });
      expect(again.statusCode).toBe(409);
      expect(again.json()).toMatchObject({ error: "request_not_pending", details: { status: "PAID" } });
    });

    it("only lets the person asked pay it, for the amount asked", async () => {
      const request = await samAsksPriya();
      expect((await post(tom.token, "/payments", { requestId: request.id })).statusCode).toBe(404);
      expect((await post(sam.token, "/payments", { requestId: request.id })).statusCode).toBe(404);
      const mismatch = await post(priya.token, "/payments", { requestId: request.id, amountMinor: 1000 });
      expect(mismatch.json()).toMatchObject({ error: "request_amount_mismatch", details: { amountMinor: 1800 } });
      expect((await post(priya.token, "/payments", { requestId: request.id, payeeUserId: sam.userId })).statusCode).toBe(400);
      expect(await prisma.payment.count()).toBe(0);
    });

    it("keeps the request open when the payment fails, so it can be paid again", async () => {
      const request = await samAsksPriya();
      const first = (await post(priya.token, "/payments", { requestId: request.id })).json();
      await ctx.app.inject({ method: "POST", url: `/dev/payments/${first.tlPaymentId}/advance`, payload: { to: "failed", failureReason: "user_canceled" } });
      expect((await get(priya.token, `/requests/${request.id}`)).json().status).toBe("PENDING");
      const second = await post(priya.token, "/payments", { requestId: request.id });
      expect(second.statusCode).toBe(201);
      await ctx.app.inject({ method: "POST", url: `/dev/payments/${second.json().tlPaymentId}/advance`, payload: { to: "settled" } });
      expect((await get(priya.token, `/requests/${request.id}`)).json()).toMatchObject({ status: "PAID", paymentId: second.json().paymentId });
    });

    it("counts against the payer's limits like any other payment", async () => {
      const request = await samAsksPriya(25000);
      await prisma.payment.create({ data: { payerUserId: priya.userId, payeeUserId: sam.userId, amountMinor: 30000, reference: "Earlier", status: "SETTLED" } });
      const response = await post(priya.token, "/payments", { requestId: request.id });
      expect(response.json().error).toBe("limit_24h");
    });

    it("marks a request paid when its payment executes after the request expired", async () => {
      const request = await samAsksPriya();
      const created = (await post(priya.token, "/payments", { requestId: request.id })).json();
      await prisma.paymentRequest.update({ where: { id: request.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
      await expireStaleRequests();
      await ctx.app.inject({ method: "POST", url: `/dev/payments/${created.tlPaymentId}/advance`, payload: { to: "executed" } });
      expect((await prisma.paymentRequest.findUniqueOrThrow({ where: { id: request.id } })).status).toBe("PAID");
    });

    it("repairs a request left open when the payment was executed but the request write was lost", async () => {
      const request = await samAsksPriya();
      const created = (await post(priya.token, "/payments", { requestId: request.id })).json();
      // Simulates a crash between the payment's transition and the request's update.
      await prisma.payment.update({ where: { id: created.paymentId }, data: { status: "EXECUTED" } });
      expect((await prisma.paymentRequest.findUniqueOrThrow({ where: { id: request.id } })).status).toBe("PENDING");
      const outcome = await applyTransition(created.paymentId, { to: "EXECUTED", source: "webhook" }, silentLog);
      expect(outcome).toMatchObject({ applied: false, reason: "duplicate" });
      expect((await prisma.paymentRequest.findUniqueOrThrow({ where: { id: request.id } })).status).toBe("PAID");
    });
  });

  it("settles a request on the next poll when its payment executed but the request write was lost", async () => {
    const request = await samAsksPriya();
    const created = (await post(priya.token, "/payments", { requestId: request.id })).json();
    // The fallback poll moved the payment on, then the process died before the request was written.
    await prisma.payment.update({ where: { id: created.paymentId }, data: { status: "EXECUTED" } });
    const result = await pollInFlightPayments(ctx.provider, silentLog);
    expect(result.requestsSettled).toBe(1);
    expect((await prisma.paymentRequest.findUniqueOrThrow({ where: { id: request.id } })).status).toBe("PAID");
    expect((await pollInFlightPayments(ctx.provider, silentLog)).requestsSettled).toBe(0);
  });

  it("closes open requests in both directions when an account is deleted", async () => {
    const fromSam = await samAsksPriya();
    const toSam = (await ask(priya.token, { payerUserId: sam.userId, amountMinor: 700, reference: "Cinema" })).json();
    expect((await ctx.app.inject({ method: "DELETE", url: "/me", headers: bearer(sam.token) })).statusCode).toBe(204);
    expect((await get(priya.token, `/requests/${fromSam.id}`)).json().status).toBe("EXPIRED");
    expect((await get(priya.token, `/requests/${toSam.id}`)).json().status).toBe("EXPIRED");
    expect((await get(priya.token, "/requests?role=incoming&status=pending")).json().requests).toEqual([]);
  });
});
