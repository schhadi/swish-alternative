import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { prisma } from "../lib/db.js";
import { FakePaymentProvider } from "../services/payments/fake.js";
import { reconcilePayment } from "../services/payments/poller.js";

const ADVANCE_STATUSES = ["authorization_required", "authorizing", "authorized", "executed", "settled", "failed"] as const;

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char] ?? char);
}

/**
 * Development-only stand-in for the bank's approval screen, registered only when PAYMENT_PROVIDER=fake.
 * It moves a fake payment along and reconciles our row straight away, so the app sees the change within its
 * 3-second poll instead of waiting for the 2-minute fallback. Nothing here exists in production.
 */
export async function devRoutes(app: FastifyInstance, options: { provider: FakePaymentProvider; returnUri: string }): Promise<void> {
  const { provider, returnUri } = options;

  async function reconcile(providerPaymentId: string): Promise<void> {
    const payment = await prisma.payment.findUnique({ where: { tlPaymentId: providerPaymentId }, select: { id: true } });
    if (payment) await reconcilePayment(payment.id, providerPaymentId, provider, "poll", app.log);
  }

  app.get("/dev/authorise/:id", async (request, reply) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(request.params);
    const record = provider.describe(id);
    if (!record) {
      return reply.status(404).type("text/html").send("<h1>No such fake payment</h1>");
    }
    const amount = `£${(record.amountMinor / 100).toFixed(2)}`;
    return reply.type("text/html").send(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fake bank · approve payment</title>
<style>
body{font-family:-apple-system,system-ui,sans-serif;background:#F6F7F5;color:#141A17;margin:0;padding:24px}
main{max-width:420px;margin:0 auto;background:#fff;border-radius:20px;padding:24px;border:1px solid #EDF0EE}
h1{font-size:20px;margin:0 0 4px}p{color:#5F6B66;margin:0 0 20px}.amount{font-size:40px;font-weight:800;letter-spacing:-2px;margin:12px 0}
button{display:block;width:100%;height:58px;border:0;border-radius:18px;font-size:17px;font-weight:700;margin-top:12px}
.approve{background:#0B6B54;color:#fff}.decline{background:#EDF0EE;color:#141A17}
</style></head><body><main>
<h1>Fake bank (development only)</h1>
<p>This page stands in for your banking app while PAYMENT_PROVIDER=fake. Status: ${escapeHtml(record.status)}</p>
<div class="amount">${amount}</div>
<p>to ${escapeHtml(record.accountHolderName)} · ref ${escapeHtml(record.reference)}</p>
<form method="post" action="/dev/authorise/${encodeURIComponent(id)}/approve"><button class="approve" type="submit">Approve</button></form>
<form method="post" action="/dev/authorise/${encodeURIComponent(id)}/decline"><button class="decline" type="submit">Decline</button></form>
</main></body></html>`);
  });

  /** Approve: authorized now, executed after 2 s, settled after 6 s, so the app's result screen shows each stage. */
  app.post("/dev/authorise/:id/approve", async (request, reply) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(request.params);
    if (!provider.advance(id, "authorized")) return reply.status(404).send({ error: "not_found", message: "No such fake payment" });
    await reconcile(id);
    setTimeout(() => {
      provider.advance(id, "executed");
      void reconcile(id);
    }, 2_000).unref();
    setTimeout(() => {
      provider.advance(id, "settled");
      void reconcile(id);
    }, 6_000).unref();
    return reply.redirect(returnUri, 303);
  });

  app.post("/dev/authorise/:id/decline", async (request, reply) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(request.params);
    if (!provider.advance(id, "failed", "user_canceled")) return reply.status(404).send({ error: "not_found", message: "No such fake payment" });
    await reconcile(id);
    return reply.redirect(returnUri, 303);
  });

  /** Scriptable version of the buttons: curl -X POST .../dev/payments/<providerPaymentId>/advance -d '{"to":"settled"}' */
  app.post("/dev/payments/:id/advance", async (request, reply) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(request.params);
    const body = z.object({ to: z.enum(ADVANCE_STATUSES), failureReason: z.string().max(80).optional() }).parse(request.body);
    if (!provider.advance(id, body.to, body.failureReason ?? null)) {
      return reply.status(404).send({ error: "not_found", message: "No such fake payment" });
    }
    await reconcile(id);
    return { ok: true };
  });
}
