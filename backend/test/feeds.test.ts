import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { bearer, createTestApp, resetDatabase, signIn, type TestContext } from "./helpers.js";

describe("feeds and providers", () => {
  let ctx: TestContext;
  let token: string;

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    ({ token } = await signIn(ctx, "07700 900001"));
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  it("lists providers including the sandbox mock bank", async () => {
    const response = await ctx.app.inject({ method: "GET", url: "/providers", headers: bearer(token) });
    expect(response.statusCode).toBe(200);
    const { providers } = response.json();
    expect(providers.length).toBeGreaterThan(10);
    expect(providers).toContainEqual({ id: "ob-monzo", displayName: "Monzo", logoUrl: null });
    expect(providers.some((p: { id: string }) => p.id === "mock-payments-gb-redirect")).toBe(true);
  });

  it("serves an empty activity feed with the final shape", async () => {
    const sent = await ctx.app.inject({ method: "GET", url: "/payments?role=sent&limit=10", headers: bearer(token) });
    expect(sent.statusCode).toBe(200);
    expect(sent.json()).toEqual({ payments: [] });
    const received = await ctx.app.inject({ method: "GET", url: "/payments?role=received", headers: bearer(token) });
    expect(received.json()).toEqual({ payments: [] });
    const bad = await ctx.app.inject({ method: "GET", url: "/payments?role=everything", headers: bearer(token) });
    expect(bad.statusCode).toBe(400);
    const missing = await ctx.app.inject({ method: "GET", url: "/payments/nope", headers: bearer(token) });
    expect(missing.statusCode).toBe(404);
  });

  it("serves empty requests and organisations until their phases land", async () => {
    expect((await ctx.app.inject({ method: "GET", url: "/requests?role=incoming", headers: bearer(token) })).json()).toEqual({ requests: [] });
    expect((await ctx.app.inject({ method: "GET", url: "/orgs", headers: bearer(token) })).json()).toEqual({ organisations: [] });
    expect((await ctx.app.inject({ method: "GET", url: "/orgs" })).statusCode).toBe(401);
  });
});
