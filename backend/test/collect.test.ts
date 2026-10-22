import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { LIMITS } from "../src/limits.js";
import { bearer, createTestApp, registerUser, resetDatabase, type TestContext } from "./helpers.js";

const HOUR_MS = 60 * 60 * 1000;

describe("Collect: organisations, collections, reminders, dues", () => {
  let ctx: TestContext;
  let sam: { token: string; userId: string };
  let priya: { token: string; userId: string };
  let tom: { token: string; userId: string };

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    sam = await registerUser(ctx, "07700 900001", "Sam Okafor", { accountNumber: "11112222" });
    priya = await registerUser(ctx, "07700 900002", "Priya Patel", { accountNumber: "87654321", providerId: "ob-starling" });
    tom = await registerUser(ctx, "07700 900003", "Tom Whitfield", null);
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  function post(token: string, url: string, payload?: Record<string, unknown>) {
    return ctx.app.inject({ method: "POST", url, headers: bearer(token), ...(payload ? { payload } : {}) });
  }

  function get(token: string, url: string) {
    return ctx.app.inject({ method: "GET", url, headers: bearer(token) });
  }

  const hockeyAccount = { sortCode: "23-05-80", accountNumber: "11223344", accountHolderName: "SOAS Hockey Club", providerId: "ob-monzo" };

  async function hockeyClub(token = sam.token) {
    const response = await post(token, "/orgs", { name: "  SOAS   Hockey Club ", kind: "CLUB", bankAccount: hockeyAccount });
    expect(response.statusCode).toBe(201);
    return response.json().organisation;
  }

  async function tripDeposit(orgId: string, overrides: Record<string, unknown> = {}) {
    const response = await post(sam.token, `/orgs/${orgId}/collections`, {
      title: "Trip deposit",
      amountPerPersonMinor: 3000,
      dueAt: new Date(Date.now() + 6 * 24 * HOUR_MS).toISOString(),
      members: [{ userId: priya.userId }, { displayName: "  Jamie   Lee " }, { userId: tom.userId, displayName: "ignored" }],
      ...overrides,
    });
    expect(response.statusCode, response.body).toBe(201);
    return response.json();
  }

  describe("organisations", () => {
    it("checks the account with the bank, stores it encrypted and makes the creator treasurer", async () => {
      const org = await hockeyClub();
      expect(org).toMatchObject({ name: "SOAS Hockey Club", kind: "CLUB", role: "TREASURER", bankName: "Monzo", collections: [] });
      const listed = (await get(sam.token, "/orgs")).json().organisations;
      expect(listed.map((row: { id: string }) => row.id)).toEqual([org.id]);
      expect((await get(priya.token, "/orgs")).json().organisations).toEqual([]);

      const stored = await prisma.organisation.findUniqueOrThrow({ where: { id: org.id }, include: { bankAccount: true } });
      expect(stored.bankAccount.userId).toBeNull();
      expect(stored.bankAccount.copStatus).toBe("MATCH");
      const raw = JSON.stringify(stored.bankAccount) + JSON.stringify(listed);
      expect(raw).not.toContain("11223344");
      expect(raw).not.toContain("230580");
    });

    it("creates nothing unless the bank confirms the name", async () => {
      const close = await post(sam.token, "/orgs", { name: "Hockey", kind: "CLUB", bankAccount: { ...hockeyAccount, accountHolderName: "soas hockey club" } });
      expect(close.json()).toEqual({ copStatus: "CLOSE_MATCH", suggestedAccountHolderName: "SOAS Hockey Club" });
      const none = await post(sam.token, "/orgs", { name: "Hockey", kind: "CLUB", bankAccount: { ...hockeyAccount, accountHolderName: "Someone Else" } });
      expect(none.json()).toEqual({ copStatus: "NO_MATCH" });
      expect((await post(sam.token, "/orgs", { name: "Hockey", kind: "CLUB", bankAccount: { ...hockeyAccount, providerId: "ob-nowhere" } })).json().error).toBe("unknown_provider");
      expect((await post(sam.token, "/orgs", { name: "Hockey", kind: "CLUB", bankAccount: { ...hockeyAccount, sortCode: "1234" } })).statusCode).toBe(400);
      expect((await post(sam.token, "/orgs", { name: " ", kind: "CLUB", bankAccount: hockeyAccount })).json().error).toBe("invalid_name");
      expect(await prisma.organisation.count()).toBe(0);
      expect(await prisma.bankAccount.count({ where: { userId: null } })).toBe(0);
    });
  });

  describe("collections", () => {
    it("creates a collection with people on Quid and plain names, and a short public link", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      expect(detail.organisationName).toBe("SOAS Hockey Club");
      expect(detail.collection).toMatchObject({ orgId: org.id, title: "Trip deposit", amountPerPersonMinor: 3000, status: "OPEN", memberCount: 3, paidCount: 0 });
      expect(detail.collection.slug).toMatch(/^[a-z2-9]{8}$/);
      expect(detail.collection.link).toBe(`http://localhost:3000/c/${detail.collection.slug}`);
      expect(detail.members.map((member: { displayName: string; isOnQuid: boolean }) => [member.displayName, member.isOnQuid])).toEqual([
        ["Priya Patel", true],
        ["Jamie Lee", false],
        ["Tom Whitfield", true],
      ]);
      expect(JSON.stringify(detail)).not.toContain(priya.userId);
      const orgs = (await get(sam.token, "/orgs")).json().organisations;
      expect(orgs[0].collections[0]).toMatchObject({ id: detail.collection.id, memberCount: 3, paidCount: 0 });
    });

    it("refuses collections nobody could pay or that make no sense", async () => {
      const org = await hockeyClub();
      const cases: [Record<string, unknown>, string][] = [
        [{ title: " " }, "invalid_title"],
        [{ amountPerPersonMinor: 0 }, "invalid_amount"],
        [{ amountPerPersonMinor: LIMITS.perPaymentMinor + 1 }, "collection_over_limit"],
        [{ dueAt: new Date(Date.now() - 3 * 24 * HOUR_MS).toISOString() }, "invalid_due_date"],
        [{ dueAt: new Date(Date.now() + 400 * 24 * HOUR_MS).toISOString() }, "invalid_due_date"],
        [{ members: [{ userId: priya.userId }, { userId: priya.userId }] }, "collection_duplicate_member"],
        [{ members: [{ userId: "00000000-0000-4000-8000-000000000000" }] }, "member_not_found"],
        [{ members: [{ displayName: " " }] }, "invalid_member_name"],
      ];
      for (const [overrides, code] of cases) {
        const response = await post(sam.token, `/orgs/${org.id}/collections`, { title: "Trip", amountPerPersonMinor: 3000, members: [], ...overrides });
        expect(response.json().error, JSON.stringify(overrides)).toBe(code);
      }
      expect((await post(priya.token, `/orgs/${org.id}/collections`, { title: "Trip", amountPerPersonMinor: 3000 })).statusCode).toBe(404);
      expect(await prisma.collection.count()).toBe(0);
    });

    it("shows the treasurer view to the treasurer only", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      const url = `/orgs/${org.id}/collections/${detail.collection.id}`;
      expect((await get(sam.token, url)).statusCode).toBe(200);
      expect((await get(priya.token, url)).statusCode).toBe(404);
      const other = await hockeyClub(priya.token);
      expect((await get(sam.token, `/orgs/${other.id}/collections/${detail.collection.id}`)).statusCode).toBe(404);
    });

    it("lists collections the user is on, for Home", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      const due = (await get(priya.token, "/collections/due")).json().collections;
      expect(due).toEqual([
        {
          memberId: expect.any(String),
          collectionId: detail.collection.id,
          title: "Trip deposit",
          organisationName: "SOAS Hockey Club",
          amountPerPersonMinor: 3000,
          dueAt: expect.any(String),
          collectionStatus: "OPEN",
          status: "UNPAID",
          paidAt: null,
          link: detail.collection.link,
        },
      ]);
      expect((await get(sam.token, "/collections/due")).json().collections).toEqual([]);
    });
  });

  describe("reminders", () => {
    it("reminds unpaid people on Quid once a day each and reports the rest", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      const [priyaMember, jamieMember, tomMember] = detail.members;
      const url = `/collections/${detail.collection.id}/remind`;
      expect((await post(priya.token, url)).statusCode).toBe(404);

      const first = (await post(sam.token, url)).json();
      expect(first.reminded).toEqual([priyaMember.id, tomMember.id]);
      expect(first.skipped).toEqual([{ memberId: jamieMember.id, reason: "not_on_quid", nextReminderAt: null }]);
      expect(first.detail.members[0]).toMatchObject({ remindCount: 1, nextReminderAt: expect.any(String) });

      const second = (await post(sam.token, url, { memberIds: [priyaMember.id] })).json();
      expect(second.reminded).toEqual([]);
      expect(second.skipped).toEqual([{ memberId: priyaMember.id, reason: "too_soon", nextReminderAt: expect.any(String) }]);

      await prisma.collectionMember.updateMany({ data: { remindedAt: new Date(Date.now() - 25 * HOUR_MS) } });
      await prisma.collectionMember.update({ where: { id: tomMember.id }, data: { status: "PAID", paidAt: new Date() } });
      const third = (await post(sam.token, url, { memberIds: [priyaMember.id, tomMember.id] })).json();
      expect(third.reminded).toEqual([priyaMember.id]);
      expect(third.skipped).toEqual([{ memberId: tomMember.id, reason: "paid", nextReminderAt: null }]);
    });

    it("sends one reminder when two arrive at once", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      const url = `/collections/${detail.collection.id}/remind`;
      const both = await Promise.all([post(sam.token, url, { memberIds: [detail.members[0].id] }), post(sam.token, url, { memberIds: [detail.members[0].id] })]);
      expect(both.map((response) => response.json().reminded.length).sort()).toEqual([0, 1]);
      expect((await prisma.collectionMember.findUniqueOrThrow({ where: { id: detail.members[0].id } })).remindCount).toBe(1);
    });
  });

  describe("account deletion", () => {
    it("takes a deleted member off Quid on every list, so nobody reminds them", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      expect((await ctx.app.inject({ method: "DELETE", url: "/me", headers: bearer(priya.token) })).statusCode).toBe(204);
      const after = (await get(sam.token, `/orgs/${org.id}/collections/${detail.collection.id}`)).json();
      expect(after.members[0]).toMatchObject({ displayName: "Deleted user", isOnQuid: false });
      const reminded = (await post(sam.token, `/collections/${detail.collection.id}/remind`)).json();
      expect(reminded.reminded).toEqual([detail.members[2].id]);
    });

    it("closes the collections of an organisation left with no treasurer", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      expect((await ctx.app.inject({ method: "DELETE", url: "/me", headers: bearer(sam.token) })).statusCode).toBe(204);
      expect(await prisma.orgMember.count({ where: { orgId: org.id } })).toBe(0);
      expect((await prisma.collection.findUniqueOrThrow({ where: { id: detail.collection.id } })).status).toBe("CLOSED");
      const page = await ctx.app.inject({ method: "GET", url: `/c/${detail.collection.slug}`, headers: { accept: "application/json" } });
      expect(page.statusCode).toBe(410);
    });
  });

  describe("paying from the app", () => {
    it("lets a member pay their share to the organisation and marks them paid when the bank executes", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      const started = await post(priya.token, "/payments", { collectionId: detail.collection.id, amountMinor: 3000 });
      expect(started.statusCode).toBe(201);
      const body = started.json();
      expect(body.firstTimePayee).toBe(true);
      expect(body.payee).toEqual({ userId: null, displayName: "SOAS Hockey Club", accountHolderName: "SOAS Hockey Club", copStatus: "MATCH", bankName: "Monzo" });
      expect(body.payment).toMatchObject({ collectionId: detail.collection.id, amountMinor: 3000, reference: "Trip deposit", counterparty: { userId: null, displayName: "SOAS Hockey Club" }, bankName: "Starling" });
      expect(JSON.stringify(body)).not.toContain("11223344");

      await ctx.app.inject({ method: "POST", url: `/dev/payments/${body.tlPaymentId}/advance`, payload: { to: "executed" } });
      const after = (await get(sam.token, `/orgs/${org.id}/collections/${detail.collection.id}`)).json();
      expect(after.collection.paidCount).toBe(1);
      expect(after.members[0]).toMatchObject({ displayName: "Priya Patel", status: "PAID", paidAt: expect.any(String) });
      expect((await get(priya.token, "/collections/due")).json().collections[0]).toMatchObject({ status: "PAID", paidAt: expect.any(String) });

      const again = await post(priya.token, "/payments", { collectionId: detail.collection.id });
      expect(again.statusCode).toBe(409);
      expect(again.json().error).toBe("already_paid");
    });

    it("only lets people on the list pay from the app, for the right amount, within their limits", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      expect((await post(sam.token, "/payments", { collectionId: detail.collection.id })).json().error).toBe("not_a_member");
      expect((await post(priya.token, "/payments", { collectionId: detail.collection.id, amountMinor: 100 })).json().error).toBe("collection_amount_mismatch");
      await prisma.payment.create({ data: { payerUserId: priya.userId, payeeUserId: sam.userId, amountMinor: 48000, reference: "Earlier", status: "SETTLED" } });
      expect((await post(priya.token, "/payments", { collectionId: detail.collection.id })).json().error).toBe("limit_24h");
      expect(await prisma.payment.count({ where: { collectionId: detail.collection.id } })).toBe(0);
    });

    it("records a second payment for someone already paid instead of losing it", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      const first = (await post(priya.token, "/payments", { collectionId: detail.collection.id })).json();
      const second = (await post(priya.token, "/payments", { collectionId: detail.collection.id })).json();
      await ctx.app.inject({ method: "POST", url: `/dev/payments/${first.tlPaymentId}/advance`, payload: { to: "executed" } });
      await ctx.app.inject({ method: "POST", url: `/dev/payments/${second.tlPaymentId}/advance`, payload: { to: "executed" } });
      const after = (await get(sam.token, `/orgs/${org.id}/collections/${detail.collection.id}`)).json();
      expect(after.members.filter((member: { displayName: string; status: string }) => member.displayName === "Priya Patel" && member.status === "PAID")).toHaveLength(2);
      expect(after.collection.paidCount).toBe(2);
      expect((await get(priya.token, "/collections/due")).json().collections).toHaveLength(1);
    });

    it("stops payments and reminders once the treasurer closes the collection", async () => {
      const org = await hockeyClub();
      const detail = await tripDeposit(org.id);
      expect((await post(priya.token, `/collections/${detail.collection.id}/close`)).statusCode).toBe(404);
      const closed = await post(sam.token, `/collections/${detail.collection.id}/close`);
      expect(closed.json().collection.status).toBe("CLOSED");
      expect((await post(priya.token, "/payments", { collectionId: detail.collection.id })).statusCode).toBe(410);
      expect((await post(sam.token, `/collections/${detail.collection.id}/remind`)).json().error).toBe("collection_closed");
      expect((await get(priya.token, "/collections/due")).json().collections[0].collectionStatus).toBe("CLOSED");
    });
  });
});
