import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { bearer, createTestApp, registerUser, resetDatabase, type TestContext } from "./helpers.js";

describe("invite and split links", () => {
  let ctx: TestContext;
  let sam: { token: string; userId: string };
  let priya: { token: string; userId: string };

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    sam = await registerUser(ctx, "07700 900001", "Sam Okafor", { accountNumber: "11112222" });
    priya = await registerUser(ctx, "07700 900002", "Priya Patel", { accountNumber: "87654321" });
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  async function invite(token: string) {
    const response = await ctx.app.inject({ method: "GET", url: "/me/invite", headers: bearer(token) });
    expect(response.statusCode).toBe(200);
    return response.json();
  }

  function page(url: string) {
    return ctx.app.inject({ method: "GET", url });
  }

  it("gives each user one stable invite link", async () => {
    const first = await invite(sam.token);
    expect(first.code).toMatch(/^[a-z2-9]{8}$/);
    expect(first.url).toBe(`http://localhost:3000/i/${first.code}`);
    expect(first.message).toContain("Quid");
    expect((await invite(sam.token)).code).toBe(first.code);
    expect((await invite(priya.token)).code).not.toBe(first.code);
    expect((await ctx.app.inject({ method: "GET", url: "/me/invite" })).statusCode).toBe(401);
  });

  it("shows the inviter's first name and nothing else about them", async () => {
    const { code } = await invite(sam.token);
    const response = await page(`/i/${code}`);
    expect(response.statusCode).toBe(200);
    expect(response.headers["content-type"]).toContain("text/html");
    expect(response.headers["cache-control"]).toBe("no-store");
    expect(response.headers["content-security-policy"]).toContain("default-src 'none'");
    expect(response.body).toContain("Sam invited you to Quid");
    expect(response.body).not.toContain("Okafor");
    expect(response.body).not.toContain("7700");
    expect(response.body).not.toContain(sam.userId);
    expect(response.body).not.toContain("<script");
  });

  it("answers 404 for unknown, malformed and deleted inviters' codes", async () => {
    expect((await page("/i/abcdefgh")).statusCode).toBe(404);
    expect((await page("/i/NOT-A-CODE")).statusCode).toBe(404);
    const { code } = await invite(sam.token);
    await ctx.app.inject({ method: "DELETE", url: "/me", headers: bearer(sam.token) });
    expect((await page(`/i/${code}`)).statusCode).toBe(404);
  });

  it("hands a split link over to the app, showing the creator's first name and the title only", async () => {
    const created = await ctx.app.inject({
      method: "POST",
      url: "/splits",
      headers: bearer(sam.token),
      payload: { title: "Pizza <night>", totalMinor: 3600, shares: [{ userId: priya.userId, amountMinor: 1800 }] },
    });
    const split = created.json();
    const response = await page(new URL(split.link).pathname);
    expect(response.statusCode).toBe(200);
    expect(response.body).toContain("Sam is splitting “Pizza &lt;night&gt;” on Quid");
    expect(response.body).toContain(`href="quid://split/${split.id}"`);
    expect(response.body).not.toContain("Pizza <night>");
    expect(response.body).not.toContain("Okafor");
    expect(response.body).not.toContain("Priya");
    expect(response.body).not.toContain("£");
    expect(response.body).not.toContain("18.00");
  });

  it("answers 404 for unknown and malformed split links", async () => {
    expect((await page("/s/00000000-0000-4000-8000-000000000000")).statusCode).toBe(404);
    expect((await page("/s/../../etc")).statusCode).toBe(404);
    expect((await page("/s/not-a-uuid")).statusCode).toBe(404);
  });
});
