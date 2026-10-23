import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { LIMITS } from "../src/limits.js";
import { appSiteAssociation } from "../src/routes/links.js";
import { logNameDisclosure } from "../src/services/payments/create.js";
import { reconcilePayment } from "../src/services/payments/poller.js";
import { ProviderError } from "../src/services/payments/provider.js";
import { bearer, createTestApp, registerUser, resetDatabase, silentLog, type TestContext } from "./helpers.js";

/** Phase 5: payer cancel, requester cancel, the daily new-payee cap, account deletion and universal links. */
describe("Phase 5 hardening", () => {
  let ctx: TestContext;
  let sam: { token: string; userId: string };
  let priya: { token: string; userId: string };

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    sam = await registerUser(ctx, "07700 900001", "Sam Okafor");
    priya = await registerUser(ctx, "07700 900002", "Priya Patel", { accountNumber: "87654321", providerId: "ob-starling" });
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  function inject(method: "GET" | "POST" | "DELETE", url: string, token: string, payload?: Record<string, unknown>) {
    return ctx.app.inject({ method, url, headers: bearer(token), ...(payload ? { payload } : {}) });
  }

  async function startPayment(token: string, payload: Record<string, unknown>) {
    const response = await inject("POST", "/payments", token, payload);
    expect(response.statusCode, response.body).toBe(201);
    return response.json() as { paymentId: string; tlPaymentId: string; firstTimePayee: boolean };
  }

  async function execute(paymentId: string, tlPaymentId: string) {
    ctx.provider.advance(tlPaymentId, "executed");
    await reconcilePayment(paymentId, tlPaymentId, ctx.provider, "poll", silentLog);
  }

  describe("POST /payments/:id/cancel", () => {
    it("cancels a payment the payer has not finished and releases it from the rolling limits", async () => {
      const first = await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 25000, reference: "Deposit" });
      const cancelled = await inject("POST", `/payments/${first.paymentId}/cancel`, sam.token);
      expect(cancelled.statusCode).toBe(200);
      expect(cancelled.json()).toMatchObject({ id: first.paymentId, status: "CANCELLED", failureReason: "canceled" });

      // £500 a day: with the cancelled £250 released, two more £250 payments fit.
      await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 25000, reference: "Deposit" });
      await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 25000, reference: "Deposit" });
      const over = await inject("POST", "/payments", sam.token, { payeeUserId: priya.userId, amountMinor: 100, reference: "More" });
      expect(over.json().error).toBe("limit_24h");

      // Cancelling again is a no-op that answers the same payment.
      const again = await inject("POST", `/payments/${first.paymentId}/cancel`, sam.token);
      expect(again.statusCode).toBe(200);
      expect(again.json().status).toBe("CANCELLED");
    });

    it("answers 404 to anyone but the payer, and 409 once the money has gone", async () => {
      const started = await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1200, reference: "Lunch" });
      expect((await inject("POST", `/payments/${started.paymentId}/cancel`, priya.token)).statusCode).toBe(404);
      expect((await inject("POST", "/payments/not-a-payment/cancel", sam.token)).statusCode).toBe(404);

      await execute(started.paymentId, started.tlPaymentId);
      const late = await inject("POST", `/payments/${started.paymentId}/cancel`, sam.token);
      expect(late.statusCode).toBe(409);
      expect(late.json().error).toBe("payment_not_cancellable");
      expect((await prisma.payment.findUniqueOrThrow({ where: { id: started.paymentId } })).status).toBe("EXECUTED");
    });

    it("reads the payment back when the provider refuses because it has already executed", async () => {
      const started = await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1200, reference: "Lunch" });
      // The bank executed it, but the webhook has not arrived: our row still says AUTHORIZING.
      ctx.provider.advance(started.tlPaymentId, "executed");
      const late = await inject("POST", `/payments/${started.paymentId}/cancel`, sam.token);
      expect(late.statusCode).toBe(409);
      expect((await prisma.payment.findUniqueOrThrow({ where: { id: started.paymentId } })).status).toBe("EXECUTED");
    });

    it("refuses once the payer has approved at the bank, without asking the provider", async () => {
      const started = await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1200, reference: "Lunch" });
      ctx.provider.advance(started.tlPaymentId, "authorized");
      await reconcilePayment(started.paymentId, started.tlPaymentId, ctx.provider, "poll", silentLog);
      let asked = 0;
      const original = ctx.provider.cancelPayment.bind(ctx.provider);
      ctx.provider.cancelPayment = async (id) => {
        asked += 1;
        return original(id);
      };
      try {
        const response = await inject("POST", `/payments/${started.paymentId}/cancel`, sam.token);
        expect(response.statusCode).toBe(409);
        expect(response.json()).toMatchObject({ error: "payment_not_cancellable", message: "You've approved this payment at your bank, so it can't be cancelled now." });
        expect(asked).toBe(0);
      } finally {
        ctx.provider.cancelPayment = original;
      }
      // The fake bank goes on to send it, and our row follows.
      await execute(started.paymentId, started.tlPaymentId);
      expect((await prisma.payment.findUniqueOrThrow({ where: { id: started.paymentId } })).status).toBe("EXECUTED");
    });

    it("answers 502 when the provider refuses a payment that is still waiting for the payer", async () => {
      const started = await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1200, reference: "Lunch" });
      const original = ctx.provider.cancelPayment.bind(ctx.provider);
      ctx.provider.cancelPayment = async () => {
        throw new ProviderError("bad request", 400, "invalid_parameters");
      };
      try {
        const response = await inject("POST", `/payments/${started.paymentId}/cancel`, sam.token);
        expect(response.statusCode).toBe(502);
        expect(response.json().error).toBe("payment_provider_unavailable");
        expect((await prisma.payment.findUniqueOrThrow({ where: { id: started.paymentId } })).status).toBe("AUTHORIZING");
      } finally {
        ctx.provider.cancelPayment = original;
      }
    });

    it("never resurrects a cancelled fake payment", async () => {
      const started = await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1200, reference: "Lunch" });
      await inject("POST", `/payments/${started.paymentId}/cancel`, sam.token);
      expect(ctx.provider.advance(started.tlPaymentId, "executed")).toBe(false);
      const approve = await ctx.app.inject({ method: "POST", url: `/dev/authorise/${started.tlPaymentId}/approve` });
      expect(approve.statusCode).toBe(409);
      expect((await prisma.payment.findUniqueOrThrow({ where: { id: started.paymentId } })).status).toBe("CANCELLED");
    });

    it("keeps the payment in flight when the provider accepts the cancel but has not applied it yet", async () => {
      const started = await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1200, reference: "Lunch" });
      const original = ctx.provider.cancelPayment.bind(ctx.provider);
      ctx.provider.cancelPayment = async () => undefined; // TrueLayer: 202 now, payment_failed by webhook later
      try {
        const response = await inject("POST", `/payments/${started.paymentId}/cancel`, sam.token);
        expect(response.statusCode).toBe(200);
        expect(response.json().status).toBe("AUTHORIZING");
      } finally {
        ctx.provider.cancelPayment = original;
      }
    });

    it("answers 502 and changes nothing when the provider cannot be reached", async () => {
      const started = await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1200, reference: "Lunch" });
      const original = ctx.provider.cancelPayment.bind(ctx.provider);
      ctx.provider.cancelPayment = async () => {
        throw new ProviderError("down", 503, null);
      };
      try {
        const response = await inject("POST", `/payments/${started.paymentId}/cancel`, sam.token);
        expect(response.statusCode).toBe(502);
        expect((await prisma.payment.findUniqueOrThrow({ where: { id: started.paymentId } })).status).toBe("AUTHORIZING");
      } finally {
        ctx.provider.cancelPayment = original;
      }
    });

    it("leaves the request it was paying open, so it can be paid again", async () => {
      const split = await inject("POST", "/splits", priya.token, { title: "Pizza", totalMinor: 1800, shares: [{ userId: sam.userId, amountMinor: 1800 }] });
      const requestId = split.json().shares[0].requestId as string;
      const started = await startPayment(sam.token, { requestId });
      await inject("POST", `/payments/${started.paymentId}/cancel`, sam.token);
      expect((await inject("GET", `/requests/${requestId}`, sam.token)).json().status).toBe("PENDING");
      await startPayment(sam.token, { requestId });
    });
  });

  describe("requester cancel", () => {
    async function splitFor(people: { userId: string }[], title = "Pizza") {
      const response = await inject("POST", "/splits", priya.token, { title, totalMinor: 1200 * people.length, shares: people.map((p) => ({ userId: p.userId, amountMinor: 1200 })) });
      expect(response.statusCode, response.body).toBe(201);
      return response.json() as { id: string; shares: { requestId: string; userId: string }[] };
    }

    it("cancels an open request: the payer can no longer pay or decline it, and it leaves their pending list", async () => {
      const split = await splitFor([sam]);
      const requestId = split.shares[0]!.requestId;
      expect((await inject("POST", `/requests/${requestId}/cancel`, sam.token)).statusCode).toBe(404);

      const cancelled = await inject("POST", `/requests/${requestId}/cancel`, priya.token);
      expect(cancelled.statusCode).toBe(200);
      expect(cancelled.json()).toMatchObject({ status: "CANCELLED" });
      expect(cancelled.json().cancelledAt).not.toBeNull();

      const pay = await inject("POST", "/payments", sam.token, { requestId });
      expect(pay.statusCode).toBe(409);
      expect(pay.json()).toMatchObject({ error: "request_not_pending", message: "This request was cancelled." });
      expect((await inject("POST", `/requests/${requestId}/decline`, sam.token)).json().error).toBe("request_not_pending");
      expect((await inject("POST", `/requests/${requestId}/remind`, priya.token)).json().error).toBe("request_not_pending");
      expect((await inject("GET", "/requests?role=incoming&status=pending", sam.token)).json().requests).toHaveLength(0);
      expect((await inject("POST", `/requests/${requestId}/cancel`, priya.token)).json().error).toBe("request_not_pending");
    });

    it("cancels a split's open shares and leaves paid and declined ones alone", async () => {
      const tom = await registerUser(ctx, "07700 900003", "Tom Whitfield", { accountNumber: "11112222" });
      const amara = await registerUser(ctx, "07700 900004", "Amara Osei", { accountNumber: "33334444" });
      const split = await splitFor([sam, tom, amara]);
      const share = (userId: string) => split.shares.find((s) => s.userId === userId)!.requestId;

      const paid = await startPayment(sam.token, { requestId: share(sam.userId) });
      await execute(paid.paymentId, paid.tlPaymentId);
      await inject("POST", `/requests/${share(tom.userId)}/decline`, tom.token);

      expect((await inject("POST", `/splits/${split.id}/cancel`, sam.token)).statusCode).toBe(404);
      const response = await inject("POST", `/splits/${split.id}/cancel`, priya.token);
      expect(response.statusCode).toBe(200);
      const body = response.json();
      expect(body.cancelled).toEqual([share(amara.userId)]);
      const statuses = Object.fromEntries(body.split.shares.map((s: { userId: string; status: string }) => [s.userId, s.status]));
      expect(statuses).toEqual({ [sam.userId]: "PAID", [tom.userId]: "DECLINED", [amara.userId]: "CANCELLED" });
      expect(body.split).toMatchObject({ pendingCount: 0, paidCount: 1 });

      const again = await inject("POST", `/splits/${split.id}/cancel`, priya.token);
      expect(again.statusCode).toBe(409);
      expect(again.json().error).toBe("split_nothing_to_cancel");
    });

    it("still marks a cancelled request paid when a payment already at the bank goes through", async () => {
      const split = await splitFor([sam]);
      const requestId = split.shares[0]!.requestId;
      const started = await startPayment(sam.token, { requestId });
      await inject("POST", `/requests/${requestId}/cancel`, priya.token);
      await execute(started.paymentId, started.tlPaymentId);
      const request = await inject("GET", `/requests/${requestId}`, priya.token);
      expect(request.json()).toMatchObject({ status: "PAID", paymentId: started.paymentId });
    });
  });

  describe("new payees per day", () => {
    it(`lets a payer start paying at most ${LIMITS.newPayeesPer24h} new people a day, then only people paid before`, async () => {
      // Priya is the first new payee of the day (her name is disclosed even though Sam then completes the payment).
      const toPriya = await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1, reference: "Hi" });
      expect(toPriya.firstTimePayee).toBe(true);
      await execute(toPriya.paymentId, toPriya.tlPaymentId);

      const payees: string[] = [];
      for (let index = 0; index < LIMITS.newPayeesPer24h - 1; index += 1) {
        const person = await registerUser(ctx, `07700 9001${String(index).padStart(2, "0")}`, `Payee ${index}`, { accountNumber: `5000${String(index).padStart(4, "0")}` });
        payees.push(person.userId);
      }
      for (const payee of payees) {
        const started = await startPayment(sam.token, { payeeUserId: payee, amountMinor: 1, reference: "Hi" });
        expect(started.firstTimePayee).toBe(true);
      }
      const extra = await registerUser(ctx, "07700 900199", "One Too Many", { accountNumber: "59999999" });
      const refused = await inject("POST", "/payments", sam.token, { payeeUserId: extra.userId, amountMinor: 1, reference: "Hi" });
      expect(refused.statusCode).toBe(429);
      expect(refused.json()).toMatchObject({ error: "new_payee_limit", details: { limit: LIMITS.newPayeesPer24h } });

      // Trying a new payee from earlier today again is not another disclosure; paying someone paid before never is.
      expect((await startPayment(sam.token, { payeeUserId: payees[0]!, amountMinor: 1, reference: "Again" })).firstTimePayee).toBe(true);
      expect((await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1, reference: "Again" })).firstTimePayee).toBe(false);

      const flagged = await prisma.payment.count({ where: { payerUserId: sam.userId, firstTimePayee: true } });
      expect(flagged).toBe(LIMITS.newPayeesPer24h + 1);
    });

    it("doesn't count a start the provider refused, since no name was shown", async () => {
      const people: string[] = [];
      for (let index = 0; index < LIMITS.newPayeesPer24h; index += 1) {
        const person = await registerUser(ctx, `07700 9002${String(index).padStart(2, "0")}`, `Outage ${index}`, { accountNumber: `6000${String(index).padStart(4, "0")}` });
        people.push(person.userId);
      }
      for (const payee of people) {
        ctx.provider.failNextCreate = new ProviderError("down", 503, null);
        const failed = await inject("POST", "/payments", sam.token, { payeeUserId: payee, amountMinor: 1, reference: "Hi" });
        expect(failed.statusCode).toBe(502);
      }
      // Ten refused starts later, a first payment to someone new still goes through.
      expect((await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1, reference: "Hi" })).firstTimePayee).toBe(true);
    });

    it("writes an audit line with ids only when a bank-held name is disclosed", () => {
      const lines: unknown[][] = [];
      const log = { ...silentLog, info: (...args: unknown[]) => lines.push(args) } as typeof silentLog;
      logNameDisclosure(log, "pay_1", "user_1", { payeeUserId: "user_2" });
      expect(lines).toEqual([[{ audit: "payee_name_disclosed", paymentId: "pay_1", payerUserId: "user_1", payeeUserId: "user_2" }, "first-time payee name disclosed"]]);
    });
  });

  describe("account deletion", () => {
    it("keeps payments for the other person, anonymised, and leaves nothing that identifies the deleted user", async () => {
      const started = await startPayment(sam.token, { payeeUserId: priya.userId, amountMinor: 1200, reference: "Lunch" });
      await execute(started.paymentId, started.tlPaymentId);
      const owed = await inject("POST", "/splits", priya.token, { title: "Cinema", totalMinor: 900, shares: [{ userId: sam.userId, amountMinor: 900 }] });
      const asked = await inject("POST", "/splits", sam.token, { title: "Taxi", totalMinor: 1500, shares: [{ userId: priya.userId, amountMinor: 1500 }] });
      await inject("GET", "/me/invite", priya.token);

      expect((await inject("DELETE", "/me", priya.token)).statusCode).toBe(204);

      // Sam's history still has the payment, now to "Deleted user", with its amount and status intact.
      const feed = (await inject("GET", "/payments?role=sent", sam.token)).json().payments;
      expect(feed).toHaveLength(1);
      expect(feed[0]).toMatchObject({ id: started.paymentId, amountMinor: 1200, status: "EXECUTED", counterparty: { userId: priya.userId, displayName: "Deleted user" } });
      const detail = await inject("GET", `/payments/${started.paymentId}`, sam.token);
      expect(detail.json().counterparty.displayName).toBe("Deleted user");

      // Nothing that identifies Priya is left on her row; her bank details and sessions are gone.
      const row = await prisma.user.findUniqueOrThrow({ where: { id: priya.userId } });
      expect(row).toMatchObject({ phoneE164: null, phoneHash: null, inviteCode: null, displayName: "Deleted user" });
      expect(await prisma.bankAccount.count({ where: { userId: priya.userId } })).toBe(0);
      expect(await prisma.session.count({ where: { userId: priya.userId } })).toBe(0);
      expect((await inject("GET", "/me", priya.token)).statusCode).toBe(401);

      // Requests either way are closed; she can't be paid or asked through them.
      const owedId = owed.json().shares[0].requestId as string;
      const askedId = asked.json().shares[0].requestId as string;
      expect((await inject("GET", `/requests/${owedId}`, sam.token)).json().status).toBe("EXPIRED");
      expect((await inject("GET", `/requests/${askedId}`, sam.token)).json().status).toBe("EXPIRED");
      const payAgain = await inject("POST", "/payments", sam.token, { payeeUserId: priya.userId, amountMinor: 100, reference: "Hi" });
      expect(payAgain.statusCode).toBeGreaterThanOrEqual(400);

      // Nothing in Sam's view of the data carries her number or account.
      const everything = JSON.stringify([feed, detail.json(), (await inject("GET", "/requests?role=outgoing", sam.token)).json()]);
      expect(everything).not.toContain("87654321");
      expect(everything).not.toContain("7700900002");
      expect(everything).not.toContain("Priya");
    });
  });

  describe("apple-app-site-association", () => {
    it("is 404 until app ids are configured", async () => {
      const response = await ctx.app.inject({ method: "GET", url: "/.well-known/apple-app-site-association" });
      expect(response.statusCode).toBe(404);
      expect(appSiteAssociation([])).toBeNull();
    });

    it("claims split links only, for the configured apps, as JSON with no redirect", async () => {
      const linked = await createTestApp({ appleAppIds: ["ABCDE12345.com.quid.app"] });
      try {
        const response = await linked.app.inject({ method: "GET", url: "/.well-known/apple-app-site-association" });
        expect(response.statusCode).toBe(200);
        expect(response.headers["content-type"]).toContain("application/json");
        expect(response.json()).toEqual({
          applinks: { details: [{ appIDs: ["ABCDE12345.com.quid.app"], components: [{ "/": "/s/*", comment: "A split's shared link opens the split in Quid" }] }] },
        });
      } finally {
        await linked.app.close();
      }
    });
  });
});
