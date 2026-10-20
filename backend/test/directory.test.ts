import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { clientPhoneHash } from "../src/lib/phoneHash.js";
import { LIMITS } from "../src/limits.js";
import { bearer, createTestApp, linkBank, resetDatabase, signIn, type TestContext } from "./helpers.js";

describe("directory lookup", () => {
  let ctx: TestContext;
  let token: string;
  let priyaId: string;
  let priyaToken: string;

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    ({ token } = await signIn(ctx, "07700 900001"));
    await ctx.app.inject({ method: "PUT", url: "/me", headers: bearer(token), payload: { displayName: "Sam Okafor" } });
    const priya = await signIn(ctx, "07700 900002");
    priyaId = priya.userId;
    priyaToken = priya.token;
    await ctx.app.inject({ method: "PUT", url: "/me", headers: bearer(priya.token), payload: { displayName: "Priya Patel" } });
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  it("returns registered contacts only, never unregistered hashes, never the caller", async () => {
    const hashes = [clientPhoneHash("+447700900002"), clientPhoneHash("+447700900003"), clientPhoneHash("+447700900001")];
    const response = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes } });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      registered: [
        { hash: clientPhoneHash("+447700900002"), userId: priyaId, displayName: "Priya Patel", firstInitials: "PP", bankName: null, canReceive: false, coolingOffUntil: null },
      ],
    });
    const raw = JSON.stringify(response.json());
    expect(raw).not.toContain(clientPhoneHash("+447700900003"));
    expect(raw).not.toContain("+44");
  });

  it("says whether a registered contact can be paid, naming the bank but never the account", async () => {
    const before = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes: [clientPhoneHash("+447700900002")] } });
    expect(before.json().registered[0]).toMatchObject({ userId: priyaId, bankName: null, canReceive: false, coolingOffUntil: null });

    await linkBank(ctx, priyaToken, { accountNumber: "87654321", accountHolderName: "Priya Patel", providerId: "ob-starling" });
    const linked = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes: [clientPhoneHash("+447700900002")] } });
    expect(linked.json().registered[0]).toMatchObject({ bankName: "Starling", canReceive: true, coolingOffUntil: null });
    expect(JSON.stringify(linked.json())).not.toContain("87654321");

    await linkBank(ctx, priyaToken, { sortCode: "20-00-00", accountNumber: "11112222", accountHolderName: "Priya Patel", providerId: "ob-starling" });
    const cooling = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes: [clientPhoneHash("+447700900002")] } });
    expect(cooling.json().registered[0]).toMatchObject({ canReceive: false, coolingOffUntil: expect.any(String) });
  });

  it("leaves out numbers that verified a code but never finished onboarding", async () => {
    await signIn(ctx, "07700 900003");
    const hashes = [clientPhoneHash("+447700900003"), clientPhoneHash("+447700900002")];
    const response = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes } });
    expect(response.json().registered.map((entry: { userId: string }) => entry.userId)).toEqual([priyaId]);
  });

  it("ignores deleted users and duplicates", async () => {
    await prisma.user.update({ where: { id: priyaId }, data: { deletedAt: new Date(), phoneHash: null, phoneE164: null } });
    const hash = clientPhoneHash("+447700900002");
    const response = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes: [hash, hash] } });
    expect(response.json()).toEqual({ registered: [] });
  });

  it("rejects malformed hashes and oversized batches", async () => {
    const bad = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes: ["+447700900002"] } });
    expect(bad.statusCode).toBe(400);
    const tooMany = Array.from({ length: LIMITS.directoryLookupMaxHashes + 1 }, (_, i) => i.toString(16).padStart(64, "0"));
    const big = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes: tooMany } });
    expect(big.statusCode).toBe(400);
    const empty = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes: [] } });
    expect(empty.statusCode).toBe(400);
  });

  it("rate-limits lookups per user", async () => {
    const hashes = [clientPhoneHash("+447700900002")];
    for (let i = 0; i < LIMITS.directoryLookupRequestsPerMinute; i += 1) {
      const response = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes } });
      expect(response.statusCode).toBe(200);
    }
    const blocked = await ctx.app.inject({ method: "POST", url: "/directory/lookup", headers: bearer(token), payload: { hashes } });
    expect(blocked.statusCode).toBe(429);
    expect(blocked.json().error).toBe("rate_limited");
  });

  it("requires auth", async () => {
    const response = await ctx.app.inject({ method: "POST", url: "/directory/lookup", payload: { hashes: [clientPhoneHash("+447700900002")] } });
    expect(response.statusCode).toBe(401);
  });
});
