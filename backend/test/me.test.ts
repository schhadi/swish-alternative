import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { decryptField } from "../src/lib/crypto.js";
import { prisma } from "../src/lib/db.js";
import { bearer, createTestApp, resetDatabase, signIn, type TestContext } from "./helpers.js";

const PHONE = "07700 900002";

describe("me", () => {
  let ctx: TestContext;
  let token: string;
  let userId: string;

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    ({ token, userId } = await signIn(ctx, PHONE));
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  it("returns the profile, no bank yet, and the server limits", async () => {
    const response = await ctx.app.inject({ method: "GET", url: "/me", headers: bearer(token) });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      user: { id: userId, phoneE164: "+447700900002", displayName: "", createdAt: expect.any(String) },
      bankAccount: null,
      limits: { perPaymentMinor: 25_000, rolling24hMinor: 50_000, rolling30dMinor: 200_000 },
    });
  });

  it("sets and validates the display name", async () => {
    const bad = await ctx.app.inject({ method: "PUT", url: "/me", headers: bearer(token), payload: { displayName: " a " } });
    expect(bad.statusCode).toBe(400);
    const ok = await ctx.app.inject({ method: "PUT", url: "/me", headers: bearer(token), payload: { displayName: "  Sam Okafor " } });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().user.displayName).toBe("Sam Okafor");
  });

  it("links a bank account on MATCH, storing details encrypted and never returning them", async () => {
    const response = await ctx.app.inject({
      method: "PUT",
      url: "/me/bank-account",
      headers: bearer(token),
      payload: { sortCode: "04-00-04", accountNumber: "11112222", accountHolderName: "Sam Okafor", providerId: "ob-monzo" },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      copStatus: "MATCH",
      bankAccount: { bankName: "Monzo", providerId: "ob-monzo", copStatus: "MATCH", verifiedAt: expect.any(String), coolingOffUntil: null },
    });
    const raw = JSON.stringify(response.json());
    expect(raw).not.toContain("040004");
    expect(raw).not.toContain("11112222");
    expect(raw).not.toContain("sortCode");
    expect(raw).not.toContain("accountNumber");

    const row = await prisma.bankAccount.findUniqueOrThrow({ where: { userId } });
    expect(row.sortCodeEnc).not.toContain("040004");
    expect(decryptField(row.sortCodeEnc)).toBe("040004");
    expect(decryptField(row.accountNumberEnc)).toBe("11112222");
    expect(decryptField(row.accountHolderNameEnc)).toBe("Sam Okafor");

    const me = await ctx.app.inject({ method: "GET", url: "/me", headers: bearer(token) });
    expect(me.json().bankAccount.bankName).toBe("Monzo");
    expect(JSON.stringify(me.json())).not.toContain("11112222");
  });

  it("asks for confirmation on CLOSE_MATCH and stores nothing", async () => {
    const response = await ctx.app.inject({
      method: "PUT",
      url: "/me/bank-account",
      headers: bearer(token),
      payload: { sortCode: "040004", accountNumber: "87654321", accountHolderName: "priya  patel" },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ copStatus: "CLOSE_MATCH", suggestedAccountHolderName: "Priya Patel" });
    expect(await prisma.bankAccount.findUnique({ where: { userId } })).toBeNull();

    const confirmed = await ctx.app.inject({
      method: "PUT",
      url: "/me/bank-account",
      headers: bearer(token),
      payload: { sortCode: "040004", accountNumber: "87654321", accountHolderName: "Priya Patel" },
    });
    expect(confirmed.json().copStatus).toBe("MATCH");
  });

  it("blocks NO_MATCH and stores nothing", async () => {
    const response = await ctx.app.inject({
      method: "PUT",
      url: "/me/bank-account",
      headers: bearer(token),
      payload: { sortCode: "99-99-99", accountNumber: "12345678", accountHolderName: "Anyone At All" },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ copStatus: "NO_MATCH" });
    expect(await prisma.bankAccount.findUnique({ where: { userId } })).toBeNull();
  });

  it("validates sort code, account number and provider", async () => {
    const cases = [
      { sortCode: "12345", accountNumber: "12345678", accountHolderName: "Sam Okafor" },
      { sortCode: "123456", accountNumber: "1234567", accountHolderName: "Sam Okafor" },
      { sortCode: "123456", accountNumber: "12345678", accountHolderName: "S" },
    ];
    for (const payload of cases) {
      const response = await ctx.app.inject({ method: "PUT", url: "/me/bank-account", headers: bearer(token), payload });
      expect(response.statusCode).toBe(400);
      expect(response.json().error).toBe("validation_error");
    }
    const unknown = await ctx.app.inject({
      method: "PUT",
      url: "/me/bank-account",
      headers: bearer(token),
      payload: { sortCode: "123456", accountNumber: "12345678", accountHolderName: "Sam Okafor", providerId: "ob-nowhere" },
    });
    expect(unknown.statusCode).toBe(400);
    expect(unknown.json().error).toBe("unknown_provider");
  });

  it("starts a cooling-off period when the account is changed, not when it is first linked", async () => {
    const link = (accountNumber: string) =>
      ctx.app.inject({
        method: "PUT",
        url: "/me/bank-account",
        headers: bearer(token),
        payload: { sortCode: "123456", accountNumber, accountHolderName: "Sam Okafor" },
      });
    expect((await link("11111111")).json().bankAccount.coolingOffUntil).toBeNull();
    // Pretend the first link happened a while ago so the change is distinguishable from creation.
    await prisma.bankAccount.updateMany({ where: { userId }, data: { createdAt: new Date(Date.now() - 60 * 60 * 1000) } });
    const changed = (await link("22222222")).json().bankAccount;
    expect(changed.coolingOffUntil).toEqual(expect.any(String));
    expect(new Date(changed.coolingOffUntil).getTime()).toBeGreaterThan(Date.now() + 23 * 60 * 60 * 1000);
    const me = await ctx.app.inject({ method: "GET", url: "/me", headers: bearer(token) });
    expect(me.json().bankAccount.coolingOffUntil).toBe(changed.coolingOffUntil);
  });

  it("deletes the account: bank details gone, phone blanked, sessions revoked", async () => {
    await ctx.app.inject({
      method: "PUT",
      url: "/me/bank-account",
      headers: bearer(token),
      payload: { sortCode: "123456", accountNumber: "12345678", accountHolderName: "Sam Okafor" },
    });
    const response = await ctx.app.inject({ method: "DELETE", url: "/me", headers: bearer(token) });
    expect(response.statusCode).toBe(204);
    expect((await ctx.app.inject({ method: "GET", url: "/me", headers: bearer(token) })).statusCode).toBe(401);
    const user = await prisma.user.findUniqueOrThrow({ where: { id: userId } });
    expect(user.phoneE164).toBeNull();
    expect(user.phoneHash).toBeNull();
    expect(user.displayName).toBe("Deleted user");
    expect(user.deletedAt).not.toBeNull();
    expect(await prisma.bankAccount.findUnique({ where: { userId } })).toBeNull();
    // The number can sign up again as a brand-new user.
    const again = await signIn(ctx, PHONE);
    expect(again.isNew).toBe(true);
    expect(again.userId).not.toBe(userId);
  });
});
