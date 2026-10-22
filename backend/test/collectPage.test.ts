import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { pollInFlightPayments } from "../src/services/payments/poller.js";
import { bearer, createTestApp, registerUser, resetDatabase, silentLog, type TestContext } from "./helpers.js";

describe("the public collection page", () => {
  let ctx: TestContext;
  let sam: { token: string; userId: string };
  let priya: { token: string; userId: string };
  let orgId: string;
  let collectionId: string;
  let slug: string;

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    sam = await registerUser(ctx, "07700 900001", "Sam Okafor", { accountNumber: "11112222" });
    priya = await registerUser(ctx, "07700 900002", "Priya Patel", { accountNumber: "87654321" });
    // The club collects into its treasurer's own account: the holder's name must never reach the public page.
    const org = await ctx.app.inject({
      method: "POST",
      url: "/orgs",
      headers: bearer(sam.token),
      payload: { name: "SOAS Hockey Club", kind: "CLUB", bankAccount: { sortCode: "20-00-00", accountNumber: "55556666", accountHolderName: "S Okafor" } },
    });
    orgId = org.json().organisation.id;
    const collection = await ctx.app.inject({
      method: "POST",
      url: `/orgs/${orgId}/collections`,
      headers: bearer(sam.token),
      payload: { title: "Trip deposit", amountPerPersonMinor: 3000, members: [{ userId: priya.userId }, { displayName: "Jamie Lee" }] },
    });
    collectionId = collection.json().collection.id;
    slug = collection.json().collection.slug;
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  function json(url: string) {
    return ctx.app.inject({ method: "GET", url, headers: { accept: "application/json" } });
  }

  function page(url: string) {
    return ctx.app.inject({ method: "GET", url, headers: { accept: "text/html,application/xhtml+xml,*/*;q=0.8" } });
  }

  function payJson(payload: Record<string, unknown>) {
    return ctx.app.inject({ method: "POST", url: `/c/${slug}/pay`, payload: { phone: "07700 900123", ...payload } });
  }

  function payForm(fields: Record<string, string>) {
    return ctx.app.inject({
      method: "POST",
      url: `/c/${slug}/pay`,
      headers: { "content-type": "application/x-www-form-urlencoded" },
      payload: new URLSearchParams(fields).toString(),
    });
  }

  async function members() {
    const detail = await ctx.app.inject({ method: "GET", url: `/orgs/${orgId}/collections/${collectionId}`, headers: bearer(sam.token) });
    return detail.json().members as { displayName: string; status: string; isOnQuid: boolean }[];
  }

  async function approve(authorisationUrl: string) {
    const providerId = authorisationUrl.split("/dev/authorise/")[1] as string;
    return ctx.app.inject({ method: "POST", url: `/dev/authorise/${providerId}/approve` });
  }

  async function execute(paymentId: string) {
    const payment = await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } });
    await ctx.app.inject({ method: "POST", url: `/dev/payments/${payment.tlPaymentId}/advance`, payload: { to: "executed" } });
  }

  const secrets = () => ["Sam", "Okafor", "Priya", "Jamie", "55556666", "200000", "20-00-00", sam.userId, priya.userId, orgId, collectionId];

  it("exposes nothing beyond title, amount and organisation name", async () => {
    const response = await json(`/c/${slug}`);
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ title: "Trip deposit", amountPerPersonMinor: 3000, organisationName: "SOAS Hockey Club" });
    const html = await page(`/c/${slug}`);
    expect(html.statusCode).toBe(200);
    expect(html.headers["content-type"]).toContain("text/html");
    expect(html.headers["cache-control"]).toBe("no-store");
    expect(html.headers["content-security-policy"]).toContain("frame-ancestors 'none'");
    expect(html.body).toContain("Pay £30.00 to SOAS Hockey Club");
    expect(html.body).toContain("Trip deposit");
    expect(html.body).toContain(`action="/c/${slug}/pay"`);
    for (const secret of secrets()) {
      expect(response.body).not.toContain(secret);
      expect(html.body).not.toContain(secret);
    }
    expect(html.body).not.toContain("<script");
  });

  it("answers 404 for unknown links and 410 once closed", async () => {
    expect((await json("/c/abcdefgh")).statusCode).toBe(404);
    expect((await json("/c/NOT-A-SLUG")).statusCode).toBe(404);
    expect((await page("/c/abcdefgh")).statusCode).toBe(404);
    await ctx.app.inject({ method: "POST", url: `/collections/${collectionId}/close`, headers: bearer(sam.token) });
    expect((await json(`/c/${slug}`)).statusCode).toBe(410);
    const closed = await page(`/c/${slug}`);
    expect(closed.statusCode).toBe(410);
    expect(closed.body).toContain("is closed");
    expect((await payJson({ displayName: "Jamie Lee" })).statusCode).toBe(410);
  });

  it("covers the definition of done: pay from the link with no app and the member flips to Paid", async () => {
    const started = await payJson({ displayName: "Jamie Lee", phone: "07700 900123" });
    expect(started.statusCode).toBe(201);
    const { paymentId, authorisationUrl } = started.json();
    expect(authorisationUrl).toContain("/dev/authorise/");
    expect(Object.keys(started.json()).sort()).toEqual(["authorisationUrl", "paymentId"]);

    const row = await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } });
    expect(row).toMatchObject({ payerUserId: null, payerDisplayName: "Jamie Lee", payeeUserId: null, collectionId, collectionMemberId: null, amountMinor: 3000, reference: "Trip deposit" });
    expect(JSON.stringify(row)).not.toContain("900123");
    expect((await members()).map((member) => member.status)).toEqual(["UNPAID", "UNPAID"]);

    const approved = await approve(authorisationUrl);
    expect(approved.statusCode).toBe(303);
    const returnUrl = new URL(approved.headers.location as string);
    expect(returnUrl.pathname).toBe("/c/return");
    const waiting = await page(returnUrl.pathname + returnUrl.search);
    expect(waiting.body).toContain("Waiting for your bank");
    expect(waiting.body).toContain('http-equiv="refresh"');

    await execute(paymentId);
    expect(await members()).toEqual([
      expect.objectContaining({ displayName: "Priya Patel", status: "UNPAID" }),
      expect.objectContaining({ displayName: "Jamie Lee", status: "PAID", isOnQuid: false }),
    ]);
    const paid = await page(returnUrl.pathname + returnUrl.search);
    expect(paid.body).toContain("you've paid SOAS Hockey Club");
    expect(paid.body).not.toContain('http-equiv="refresh"');
  });

  it("matches a link payer to an unpaid name however it is typed, and adds anyone not on the list", async () => {
    const jamie = (await payJson({ displayName: "  jamie   LEE " })).json();
    const alex = (await payJson({ displayName: "Alex Morgan" })).json();
    await execute(jamie.paymentId);
    await execute(alex.paymentId);
    expect((await members()).map((member) => [member.displayName, member.status])).toEqual([
      ["Priya Patel", "UNPAID"],
      ["Jamie Lee", "PAID"],
      ["Alex Morgan", "PAID"],
    ]);
  });

  it("leaves the list alone when a link payment is abandoned or fails, and counts two payments under one name twice", async () => {
    await payJson({ displayName: "Jamie Lee" });
    const failed = (await payJson({ displayName: "Jamie Lee" })).json();
    const failedRow = await prisma.payment.findUniqueOrThrow({ where: { id: failed.paymentId } });
    await ctx.app.inject({ method: "POST", url: `/dev/payments/${failedRow.tlPaymentId}/advance`, payload: { to: "failed", failureReason: "user_canceled" } });
    expect((await members()).length).toBe(2);

    const first = (await payJson({ displayName: "Jamie Lee" })).json();
    const second = (await payJson({ displayName: "Jamie Lee" })).json();
    await execute(first.paymentId);
    await execute(second.paymentId);
    expect((await members()).map((member) => [member.displayName, member.status])).toEqual([
      ["Priya Patel", "UNPAID"],
      ["Jamie Lee", "PAID"],
      ["Jamie Lee", "PAID"],
    ]);
  });

  it("sends the page's form straight to the bank, or shows it again with the problem", async () => {
    const redirected = await payForm({ displayName: "Jamie Lee", phone: "07700 900123" });
    expect(redirected.statusCode).toBe(303);
    expect(redirected.headers.location).toContain("/dev/authorise/");

    const noName = await payForm({ displayName: "  ", phone: "" });
    expect(noName.statusCode).toBe(400);
    expect(noName.headers["content-type"]).toContain("text/html");
    expect(noName.body).toContain("Enter your name");
    expect(noName.body).toContain("<form");

    const badPhone = await payForm({ displayName: "Jamie <b>Lee</b>", phone: "12345" });
    expect(badPhone.statusCode).toBe(400);
    expect(badPhone.body).toContain("Enter a UK mobile number");
    expect(badPhone.body).toContain("Jamie &lt;b&gt;Lee&lt;/b&gt;");
    expect(badPhone.body).not.toContain("<b>Lee</b>");
  });

  it("shows a failed payment with a way to try again, and 404 for unknown payments", async () => {
    const started = (await payJson({ displayName: "Jamie Lee" })).json();
    const row = await prisma.payment.findUniqueOrThrow({ where: { id: started.paymentId } });
    await ctx.app.inject({ method: "POST", url: `/dev/payments/${row.tlPaymentId}/advance`, payload: { to: "failed" } });
    const failed = await page(`/c/return?payment_id=${row.tlPaymentId}`);
    expect(failed.body).toContain("didn't go through");
    expect(failed.body).toContain(`href="/c/${slug}"`);
    expect((await page("/c/return?payment_id=fake_nope")).statusCode).toBe(404);
    expect((await page("/c/return")).statusCode).toBe(404);
  });

  it("settles a link payment on the next poll when the member write was lost", async () => {
    const started = (await payJson({ displayName: "Jamie Lee" })).json();
    await prisma.payment.update({ where: { id: started.paymentId }, data: { status: "EXECUTED" } });
    expect((await pollInFlightPayments(ctx.provider, silentLog)).requestsSettled).toBe(1);
    expect((await members())[1]).toMatchObject({ displayName: "Jamie Lee", status: "PAID" });
    expect((await pollInFlightPayments(ctx.provider, silentLog)).requestsSettled).toBe(0);
  });

  it("needs the payer's mobile number, which the payment service requires, and never keeps it", async () => {
    const missing = await payJson({ displayName: "Jamie Lee", phone: "" });
    expect(missing.statusCode).toBe(400);
    expect(missing.json().error).toBe("phone_required");
    const form = await payForm({ displayName: "Jamie Lee", phone: "" });
    expect(form.statusCode).toBe(400);
    expect(form.body).toContain("Enter your mobile number");
    expect(await prisma.payment.count()).toBe(0);
  });

  it("lets a browser approve on the fake bank page, whose form posts an empty urlencoded body", async () => {
    const { paymentId, authorisationUrl } = (await payJson({ displayName: "Jamie Lee" })).json();
    const providerId = authorisationUrl.split("/dev/authorise/")[1] as string;
    const approved = await ctx.app.inject({
      method: "POST",
      url: `/dev/authorise/${providerId}/approve`,
      headers: { "content-type": "application/x-www-form-urlencoded" },
      payload: "",
    });
    expect(approved.statusCode).toBe(303);
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } })).status).toBe("AUTHORIZED");
  });

  it("gives the return page its own bucket, stops refreshing after about two minutes, and shows a page when a cap is hit", async () => {
    const limited = await createTestApp({ publicPagesPerMinutePerIp: 1 });
    try {
      const { authorisationUrl } = (await limited.app.inject({ method: "POST", url: `/c/${slug}/pay`, payload: { displayName: "Jamie Lee", phone: "07700 900123" } })).json();
      const providerId = authorisationUrl.split("/dev/authorise/")[1] as string;
      const browser = { accept: "text/html" };
      expect((await limited.app.inject({ method: "GET", url: `/c/${slug}`, headers: browser })).statusCode).toBe(200);
      const capped = await limited.app.inject({ method: "GET", url: `/c/${slug}`, headers: browser });
      expect(capped.statusCode).toBe(429);
      expect(capped.headers["content-type"]).toContain("text/html");
      expect(capped.body).toContain("Too many tries");
      expect((await limited.app.inject({ method: "GET", url: `/c/${slug}`, headers: { accept: "application/json" } })).json().error).toBe("rate_limited");

      const waiting = await limited.app.inject({ method: "GET", url: `/c/return?payment_id=${providerId}`, headers: browser });
      expect(waiting.statusCode).toBe(200);
      expect(waiting.body).toContain(`url=/c/return?payment_id=${providerId}&amp;n=1`);
      const last = await limited.app.inject({ method: "GET", url: `/c/return?payment_id=${providerId}&n=40`, headers: browser });
      expect(last.body).toContain("Still waiting for your bank");
      expect(last.body).not.toContain('http-equiv="refresh"');
    } finally {
      await limited.app.close();
    }
  });

  it("caps payments started from the page per IP", async () => {
    const limited = await createTestApp({ publicPaymentsPerMinutePerIp: 2 });
    try {
      const send = () => limited.app.inject({ method: "POST", url: `/c/${slug}/pay`, payload: { displayName: "Jamie Lee", phone: "07700 900123" } });
      expect((await send()).statusCode).toBe(201);
      expect((await send()).statusCode).toBe(201);
      expect((await send()).statusCode).toBe(429);
    } finally {
      await limited.app.close();
    }
  });
});
