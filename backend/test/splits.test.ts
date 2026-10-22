import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { LIMITS } from "../src/limits.js";
import { referenceFromTitle } from "../src/services/requests/rules.js";
import { bearer, createTestApp, registerUser, resetDatabase, type TestContext } from "./helpers.js";

describe("splits", () => {
  let ctx: TestContext;
  let sam: { token: string; userId: string };
  let priya: { token: string; userId: string };
  let tom: { token: string; userId: string };

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    sam = await registerUser(ctx, "07700 900001", "Sam Okafor", { accountNumber: "11112222", providerId: "ob-monzo" });
    priya = await registerUser(ctx, "07700 900002", "Priya Patel", { accountNumber: "87654321", providerId: "ob-starling" });
    tom = await registerUser(ctx, "07700 900003", "Tom Whitfield", null);
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  function split(token: string, payload: Record<string, unknown>) {
    return ctx.app.inject({ method: "POST", url: "/splits", headers: bearer(token), payload });
  }

  function post(token: string, url: string, payload?: Record<string, unknown>) {
    return ctx.app.inject({ method: "POST", url, headers: bearer(token), ...(payload ? { payload } : {}) });
  }

  function get(token: string, url: string) {
    return ctx.app.inject({ method: "GET", url, headers: bearer(token) });
  }

  async function dinner() {
    // £60 between three: Sam keeps his own £20 share and asks the other two.
    const response = await split(sam.token, {
      title: "Café dinner!",
      totalMinor: 6000,
      shares: [
        { userId: tom.userId, amountMinor: 2000 },
        { userId: priya.userId, amountMinor: 2000 },
      ],
    });
    expect(response.statusCode).toBe(201);
    return response.json();
  }

  async function payShare(token: string, splitId: string, to: "executed" | "settled" = "executed") {
    const request = (await get(token, "/requests?role=incoming&status=pending")).json().requests.find((row: { splitId: string }) => row.splitId === splitId);
    const created = (await post(token, "/payments", { requestId: request.id })).json();
    await ctx.app.inject({ method: "POST", url: `/dev/payments/${created.tlPaymentId}/advance`, payload: { to } });
    return request.id as string;
  }

  it("creates one request per share and reports progress from the creator's side", async () => {
    const body = await dinner();
    expect(body).toMatchObject({
      title: "Café dinner!",
      totalMinor: 6000,
      creatorShareMinor: 2000,
      requestedMinor: 4000,
      paidMinor: 0,
      shareCount: 2,
      paidCount: 0,
      pendingCount: 2,
      isComplete: false,
      link: `http://localhost:3000/s/${body.id}`,
    });
    expect(body.shares.map((share: { displayName: string }) => share.displayName)).toEqual(["Priya Patel", "Tom Whitfield"]);
    expect(body.shares[0]).toMatchObject({ userId: priya.userId, amountMinor: 2000, status: "PENDING", remindCount: 0, nextReminderAt: null, paymentId: null });

    const incoming = (await get(priya.token, "/requests?role=incoming")).json().requests;
    expect(incoming).toHaveLength(1);
    expect(incoming[0]).toMatchObject({ splitId: body.id, splitTitle: "Café dinner!", reference: "Cafe dinner", amountMinor: 2000, requester: { userId: sam.userId } });
    expect((await get(sam.token, "/requests?role=outgoing")).json().requests).toHaveLength(2);
    expect(await prisma.splitShare.count({ where: { splitId: body.id } })).toBe(2);
  });

  it("turns any title into a Faster Payments reference", () => {
    expect(referenceFromTitle("Café dinner!")).toBe("Cafe dinner");
    expect(referenceFromTitle("Zoë's 21st birthday weekend")).toBe("Zoes 21st birthday");
    expect(referenceFromTitle("  Rent   & bills / Oct ")).toBe("Rent & bills / Oct");
    expect(referenceFromTitle("🍕🍕")).toBe("Quid split");
    expect(referenceFromTitle("李明的生日")).toBe("Quid split");
  });

  it("counts the title in characters as people see them, emoji and flags included", async () => {
    const forty = "a".repeat(36) + "🍕🇬🇧👩‍👩‍👧🎉";
    const accepted = await split(sam.token, { title: forty, totalMinor: 1000, shares: [{ userId: priya.userId, amountMinor: 1000 }] });
    expect(accepted.statusCode).toBe(201);
    const refused = await split(sam.token, { title: forty + "!", totalMinor: 1000, shares: [{ userId: priya.userId, amountMinor: 1000 }] });
    expect(refused.json().error).toBe("invalid_title");
  });

  it("finds the viewer's own request in a split however many requests they have", async () => {
    const body = await dinner();
    for (let index = 0; index < 3; index += 1) {
      await split(sam.token, { title: `Other ${index}`, totalMinor: 500, shares: [{ userId: priya.userId, amountMinor: 500 }] });
    }
    const filtered = (await get(priya.token, `/requests?role=incoming&splitId=${body.id}&limit=1`)).json().requests;
    expect(filtered).toHaveLength(1);
    expect(filtered[0]).toMatchObject({ splitId: body.id, amountMinor: 2000 });
    expect((await get(tom.token, `/requests?role=incoming&splitId=${body.id}`)).json().requests[0].payerUserId).toBe(tom.userId);
    expect((await get(sam.token, `/requests?role=incoming&splitId=${body.id}`)).json().requests).toEqual([]);
  });

  it("validates the split before writing anything", async () => {
    const share = (userId: string, amountMinor = 1000) => ({ userId, amountMinor });
    const cases: [Record<string, unknown>, string][] = [
      [{ title: "  ", totalMinor: 1000, shares: [share(priya.userId)] }, "invalid_title"],
      [{ title: "x".repeat(LIMITS.requestTitleMaxLength + 1), totalMinor: 1000, shares: [share(priya.userId)] }, "invalid_title"],
      [{ title: "Dinner", totalMinor: 0, shares: [share(priya.userId)] }, "invalid_amount"],
      [{ title: "Dinner", totalMinor: LIMITS.splitMaxTotalMinor + 1, shares: [share(priya.userId)] }, "split_total_too_large"],
      [{ title: "Dinner", totalMinor: 1000, shares: [] }, "split_no_people"],
      [{ title: "Dinner", totalMinor: 5000, shares: [share(priya.userId), share(priya.userId)] }, "split_duplicate_person"],
      [{ title: "Dinner", totalMinor: 5000, shares: [share(sam.userId)] }, "self_request"],
      [{ title: "Dinner", totalMinor: 1500, shares: [share(priya.userId), share(tom.userId)] }, "split_shares_exceed_total"],
      [{ title: "Dinner", totalMinor: 30000, shares: [share(priya.userId, LIMITS.perPaymentMinor + 1)] }, "request_over_limit"],
      [{ title: "Dinner", totalMinor: 5000, shares: [share(priya.userId, 0)] }, "invalid_amount"],
      [{ title: "Dinner", totalMinor: 5000, shares: [share("00000000-0000-4000-8000-000000000000")] }, "payer_not_found"],
    ];
    for (const [payload, code] of cases) {
      const response = await split(sam.token, payload);
      expect(response.json().error, JSON.stringify(payload).slice(0, 80)).toBe(code);
    }
    const many = Array.from({ length: LIMITS.splitMaxShares + 1 }, (_, index) => share(`user-${index}`, 100));
    expect((await split(sam.token, { title: "Party", totalMinor: 100_000, shares: many })).json().error).toBe("split_too_many_people");
    // Tom has no bank account: people could not pay him.
    expect((await split(tom.token, { title: "Dinner", totalMinor: 1000, shares: [share(priya.userId)] })).json().error).toBe("requester_not_payable");
    expect(await prisma.split.count()).toBe(0);
    expect(await prisma.paymentRequest.count()).toBe(0);
  });

  it("shows a split to its creator only, and lists the creator's splits newest first", async () => {
    const first = await dinner();
    const second = (await split(sam.token, { title: "Taxi", totalMinor: 900, shares: [{ userId: priya.userId, amountMinor: 450 }] })).json();
    expect((await get(sam.token, `/splits/${first.id}`)).statusCode).toBe(200);
    expect((await get(priya.token, `/splits/${first.id}`)).statusCode).toBe(404);
    expect((await get(sam.token, "/splits/not-a-split")).statusCode).toBe(404);
    expect((await get(sam.token, "/splits")).json().splits.map((row: { id: string }) => row.id)).toEqual([second.id, first.id]);
    expect((await get(priya.token, "/splits")).json().splits).toEqual([]);
  });

  it("is complete once nobody is left to pay: paid and declined shares both count", async () => {
    const body = await dinner();
    await payShare(priya.token, body.id);
    const afterPriya = (await get(sam.token, `/splits/${body.id}`)).json();
    expect(afterPriya).toMatchObject({ paidCount: 1, paidMinor: 2000, pendingCount: 1, isComplete: false });
    expect(afterPriya.shares[0]).toMatchObject({ status: "PAID", paidAt: expect.any(String), paymentId: expect.any(String) });

    const tomRequest = (await get(tom.token, "/requests?role=incoming")).json().requests[0];
    await post(tom.token, `/requests/${tomRequest.id}/decline`);
    expect((await get(sam.token, `/splits/${body.id}`)).json()).toMatchObject({ paidCount: 1, pendingCount: 0, isComplete: true });
  });

  it("covers the definition of done: one person, one share, paid, 1 of 1", async () => {
    const body = (await split(sam.token, { title: "Concert tickets", totalMinor: 4500, shares: [{ userId: priya.userId, amountMinor: 4500 }] })).json();
    expect(body).toMatchObject({ shareCount: 1, paidCount: 0, creatorShareMinor: 0 });
    await payShare(priya.token, body.id, "settled");
    expect((await get(sam.token, `/splits/${body.id}`)).json()).toMatchObject({ shareCount: 1, paidCount: 1, isComplete: true });
  });

  it("reminds everyone unpaid at most once a day each, and says who was skipped", async () => {
    const body = await dinner();
    const priyaRequestId = body.shares[0].requestId;
    const tomRequestId = body.shares[1].requestId;

    expect((await post(priya.token, `/splits/${body.id}/remind`)).statusCode).toBe(404);
    const first = (await post(sam.token, `/splits/${body.id}/remind`)).json();
    expect(first.reminded.sort()).toEqual([priyaRequestId, tomRequestId].sort());
    expect(first.skipped).toEqual([]);
    expect(first.split.shares.every((share: { remindCount: number }) => share.remindCount === 1)).toBe(true);

    const second = (await post(sam.token, `/splits/${body.id}/remind`)).json();
    expect(second.reminded).toEqual([]);
    expect(second.skipped).toEqual(
      expect.arrayContaining([
        { requestId: priyaRequestId, reason: "too_soon", nextReminderAt: expect.any(String) },
        { requestId: tomRequestId, reason: "too_soon", nextReminderAt: expect.any(String) },
      ]),
    );

    await prisma.paymentRequest.updateMany({ data: { lastRemindedAt: new Date(Date.now() - 25 * 60 * 60 * 1000) } });
    await payShare(priya.token, body.id);
    const third = (await post(sam.token, `/splits/${body.id}/remind`, { requestIds: [priyaRequestId, tomRequestId] })).json();
    expect(third.reminded).toEqual([tomRequestId]);
    expect(third.skipped).toEqual([{ requestId: priyaRequestId, reason: "not_pending", nextReminderAt: null }]);
  });

  it("nudges one person from the split detail", async () => {
    const body = await dinner();
    const response = await post(sam.token, `/requests/${body.shares[1].requestId}/remind`);
    expect(response.statusCode).toBe(200);
    const detail = (await get(sam.token, `/splits/${body.id}`)).json();
    expect(detail.shares[1]).toMatchObject({ remindCount: 1, nextReminderAt: expect.any(String) });
    expect(detail.shares[0]).toMatchObject({ remindCount: 0, nextReminderAt: null });
  });
});
