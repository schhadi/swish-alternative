import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { LIMITS } from "../src/limits.js";
import { bearer, createTestApp, resetDatabase, signIn, type TestContext } from "./helpers.js";

const PHONE = "07700 900001";

describe("auth", () => {
  let ctx: TestContext;

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    ctx.sms.messages = [];
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  it("signs up a new user with a logged code and returns a token", async () => {
    const start = await ctx.app.inject({ method: "POST", url: "/auth/otp/start", payload: { phone: PHONE } });
    expect(start.statusCode).toBe(200);
    expect(start.json()).toEqual({ phoneE164: "+447700900001", expiresInSeconds: 300 });
    expect(ctx.sms.messages).toHaveLength(1);
    expect(ctx.sms.messages[0]?.phoneE164).toBe("+447700900001");
    const code = ctx.sms.lastCode();

    const verify = await ctx.app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: "+44 7700 900001", code } });
    expect(verify.statusCode).toBe(200);
    const body = verify.json();
    expect(body.isNew).toBe(true);
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(body.user).toMatchObject({ phoneE164: "+447700900001", displayName: "" });
    expect(body.user.phoneHash).toBeUndefined();

    const stored = await prisma.user.findUniqueOrThrow({ where: { phoneE164: "+447700900001" } });
    expect(stored.phoneHash).toMatch(/^[0-9a-f]{64}$/);
    const session = await prisma.session.findFirstOrThrow({ where: { userId: stored.id } });
    expect(session.tokenHash).not.toBe(body.token);
  });

  it("recognises an existing user on the next sign-in", async () => {
    const first = await signIn(ctx, PHONE);
    const second = await signIn(ctx, PHONE);
    expect(first.isNew).toBe(true);
    expect(second.isNew).toBe(false);
    expect(second.userId).toBe(first.userId);
    expect(second.token).not.toBe(first.token);
  });

  it("rejects numbers that are not UK", async () => {
    const response = await ctx.app.inject({ method: "POST", url: "/auth/otp/start", payload: { phone: "+1 555 123 4567" } });
    expect(response.statusCode).toBe(400);
    expect(response.json().error).toBe("invalid_phone");
    expect(ctx.sms.messages).toHaveLength(0);
  });

  it("locks the code after five wrong attempts", async () => {
    await ctx.app.inject({ method: "POST", url: "/auth/otp/start", payload: { phone: PHONE } });
    const code = ctx.sms.lastCode();
    const wrong = code === "000000" ? "000001" : "000000";
    for (let attempt = 1; attempt < LIMITS.otpMaxAttempts; attempt += 1) {
      const response = await ctx.app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: PHONE, code: wrong } });
      expect(response.statusCode).toBe(400);
      expect(response.json()).toMatchObject({ error: "otp_invalid", details: { attemptsRemaining: LIMITS.otpMaxAttempts - attempt } });
    }
    const locked = await ctx.app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: PHONE, code: wrong } });
    expect(locked.statusCode).toBe(429);
    expect(locked.json().error).toBe("otp_locked");
    // Even the right code no longer works on a locked challenge.
    const late = await ctx.app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: PHONE, code } });
    expect(late.statusCode).toBe(429);
    // A fresh code works again.
    await ctx.app.inject({ method: "POST", url: "/auth/otp/start", payload: { phone: PHONE } });
    const fresh = await ctx.app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: PHONE, code: ctx.sms.lastCode() } });
    expect(fresh.statusCode).toBe(200);
  });

  it("rejects expired and reused codes", async () => {
    await ctx.app.inject({ method: "POST", url: "/auth/otp/start", payload: { phone: PHONE } });
    const code = ctx.sms.lastCode();
    await prisma.otpChallenge.updateMany({ where: { phoneE164: "+447700900001" }, data: { expiresAt: new Date(Date.now() - 1_000) } });
    const expired = await ctx.app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: PHONE, code } });
    expect(expired.statusCode).toBe(400);
    expect(expired.json().error).toBe("otp_expired");

    await ctx.app.inject({ method: "POST", url: "/auth/otp/start", payload: { phone: PHONE } });
    const good = ctx.sms.lastCode();
    const ok = await ctx.app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: PHONE, code: good } });
    expect(ok.statusCode).toBe(200);
    const reused = await ctx.app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: PHONE, code: good } });
    expect(reused.statusCode).toBe(400);
    expect(reused.json().error).toBe("otp_missing");
  });

  it("limits how often a number can request codes", async () => {
    for (let i = 0; i < LIMITS.otpStartsPerWindow; i += 1) {
      const response = await ctx.app.inject({ method: "POST", url: "/auth/otp/start", payload: { phone: PHONE } });
      expect(response.statusCode).toBe(200);
    }
    const blocked = await ctx.app.inject({ method: "POST", url: "/auth/otp/start", payload: { phone: PHONE } });
    expect(blocked.statusCode).toBe(429);
    expect(blocked.json().error).toBe("otp_rate_limited");
  });

  it("validates the code shape before touching the database", async () => {
    const response = await ctx.app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone: PHONE, code: "12" } });
    expect(response.statusCode).toBe(400);
    expect(response.json().error).toBe("validation_error");
  });

  it("requires a valid bearer token and honours logout", async () => {
    expect((await ctx.app.inject({ method: "GET", url: "/me" })).statusCode).toBe(401);
    expect((await ctx.app.inject({ method: "GET", url: "/me", headers: bearer("not-a-real-token-at-all") })).statusCode).toBe(401);
    const { token } = await signIn(ctx, PHONE);
    expect((await ctx.app.inject({ method: "GET", url: "/me", headers: bearer(token) })).statusCode).toBe(200);
    const logout = await ctx.app.inject({ method: "POST", url: "/auth/logout", headers: bearer(token) });
    expect(logout.statusCode).toBe(204);
    expect((await ctx.app.inject({ method: "GET", url: "/me", headers: bearer(token) })).statusCode).toBe(401);
  });

  it("rejects expired sessions", async () => {
    const { token, userId } = await signIn(ctx, PHONE);
    await prisma.session.updateMany({ where: { userId }, data: { expiresAt: new Date(Date.now() - 1_000) } });
    expect((await ctx.app.inject({ method: "GET", url: "/me", headers: bearer(token) })).statusCode).toBe(401);
  });
});
