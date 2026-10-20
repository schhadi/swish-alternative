import type { FastifyInstance } from "fastify";
import { Prisma } from "@prisma/client";
import { prisma } from "../lib/db.js";
import { applyTransition } from "../services/payments/stateMachine.js";
import { mapWebhookEvent, parseWebhookEvent, WebhookVerificationError } from "../services/truelayer/webhooks.js";

export interface WebhookRouteOptions {
  /** Signed timestamps older (or newer) than this are refused. Infinity disables the check (tests with recorded fixtures). */
  maxAgeSeconds: number;
}

/**
 * POST /webhooks/truelayer (docs/SPEC.md section 5): no bearer auth; the Tl-Signature header proves TrueLayer sent
 * it. Webhooks are the source of truth for payment status, so after verification the route always answers 200
 * (duplicates, unknown payments and unknown event types included) and only a database failure yields a 5xx, which
 * makes TrueLayer retry.
 */
export async function webhookRoutes(app: FastifyInstance, options: WebhookRouteOptions): Promise<void> {
  // The signature covers the exact bytes TrueLayer sent, so this plugin keeps the body as a string.
  app.addContentTypeParser("application/json", { parseAs: "string" }, (_request, body, done) => {
    done(null, body);
  });

  app.post("/webhooks/truelayer", { config: { rateLimit: false } }, async (request, reply) => {
    const signature = request.headers["tl-signature"];
    if (typeof signature !== "string" || signature.length === 0) {
      return reply.status(403).send({ error: "webhook_unsigned", message: "Missing Tl-Signature" });
    }
    const body = typeof request.body === "string" ? request.body : "";
    const headers: Record<string, string> = {};
    for (const [name, value] of Object.entries(request.headers)) {
      if (typeof value === "string") headers[name] = value;
    }
    const path = new URL(request.raw.url ?? "/webhooks/truelayer", "http://localhost").pathname;
    try {
      await app.services.webhookVerifier.verify({ signature, path, headers, body });
    } catch (error) {
      request.log.warn({ reason: error instanceof Error ? error.message : String(error) }, "webhook rejected");
      return reply.status(403).send({ error: "webhook_invalid", message: "Signature verification failed" });
    }
    const timestamp = headers["x-tl-webhook-timestamp"];
    if (Number.isFinite(options.maxAgeSeconds)) {
      const sentAt = timestamp ? Date.parse(timestamp) : Number.NaN;
      if (!Number.isFinite(sentAt) || Math.abs(Date.now() - sentAt) > options.maxAgeSeconds * 1000) {
        request.log.warn({ timestamp }, "webhook rejected: stale or missing timestamp");
        return reply.status(403).send({ error: "webhook_stale", message: "Webhook timestamp is missing or too old" });
      }
    }

    let event;
    try {
      event = parseWebhookEvent(body);
    } catch (error) {
      request.log.warn({ reason: error instanceof WebhookVerificationError ? error.message : "unparseable" }, "webhook body unusable");
      return reply.status(400).send({ error: "webhook_malformed", message: "Body is not a TrueLayer event" });
    }
    const mapped = mapWebhookEvent(event);

    try {
      await prisma.webhookEvent.create({ data: { id: event.event_id, type: event.event_type, paymentId: null } });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
        request.log.info({ eventId: event.event_id, eventType: event.event_type }, "webhook redelivered; already applied");
        return { received: true, duplicate: true };
      }
      throw error;
    }

    if (!mapped.status) {
      request.log.info({ eventId: event.event_id, eventType: event.event_type }, "webhook event type not handled");
      return { received: true, applied: false };
    }
    if (!mapped.providerPaymentId) {
      request.log.warn({ eventId: event.event_id, eventType: event.event_type }, "webhook event without payment_id");
      return { received: true, applied: false };
    }
    const payment = await prisma.payment.findUnique({
      where: { tlPaymentId: mapped.providerPaymentId },
      select: { id: true, payerUserId: true, payeeUserId: true },
    });
    if (!payment) {
      request.log.warn({ eventId: event.event_id, eventType: event.event_type }, "webhook for unknown payment");
      return { received: true, applied: false };
    }
    await prisma.webhookEvent.update({ where: { id: event.event_id }, data: { paymentId: payment.id } });
    const outcome = await applyTransition(
      payment.id,
      { to: mapped.status, source: "webhook", failureReason: mapped.failureReason, providerStatus: mapped.providerStatus },
      request.log,
    );
    if (outcome.applied) {
      // Real push notifications are out of scope for v1 (docs/SPEC.md section 10); the log line is the stub.
      request.log.info(
        { paymentId: payment.id, status: outcome.to, recipients: [payment.payerUserId, payment.payeeUserId].filter(Boolean) },
        "push notification (stub)",
      );
    }
    return { received: true, applied: outcome.applied };
  });
}
