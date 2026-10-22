import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import { prisma } from "../lib/db.js";
import { HttpError } from "../lib/errors.js";
import { escapeHtml, sendHtmlPage } from "../lib/html.js";
import { normaliseUKPhone } from "../lib/phone.js";
import { createCollectionPayment, SLUG_PATTERN } from "../services/collections/service.js";
import { visibleLength } from "../services/requests/rules.js";

/**
 * The public side of Collect (docs/SPEC.md section 5 and screen 9): GET /c/:slug and POST /c/:slug/pay, no auth,
 * for people paying from a link or QR code without the app. Answers JSON when asked for it and a minimal HTML page
 * otherwise. Nothing here says anything beyond the collection's title, amount and organisation name: no members,
 * no treasurer, no account details (docs/DECISIONS.md #85).
 */

const PayBody = z.object({
  displayName: z.string().max(200).optional(),
  phone: z.string().max(40).optional(),
});

type PublicCollection = { slug: string; title: string; amountPerPersonMinor: number; status: string; org: { name: string } };

function amount(minor: number): string {
  return `£${(minor / 100).toFixed(2)}`;
}

function wantsJson(request: FastifyRequest): boolean {
  const accept = request.headers.accept ?? "";
  return accept.includes("application/json") && !accept.includes("text/html");
}

async function findBySlug(slug: string): Promise<PublicCollection | null> {
  if (!SLUG_PATTERN.test(slug)) return null;
  return prisma.collection.findUnique({
    where: { slug },
    select: { slug: true, title: true, amountPerPersonMinor: true, status: true, org: { select: { name: true } } },
  });
}

function notFoundPage(reply: FastifyReply) {
  return sendHtmlPage(reply, 404, "Collection not found", `<h1>This link isn't valid</h1>
<p>It may have been mistyped. Ask whoever shared it for the link again.</p>`);
}

function closedPage(reply: FastifyReply, collection: PublicCollection) {
  return sendHtmlPage(reply, 410, `${collection.org.name}: closed`, `<h1>${escapeHtml(collection.title)} is closed</h1>
<p>${escapeHtml(collection.org.name)} isn't taking payments for this any more. Nothing has been charged.</p>`);
}

function payPage(reply: FastifyReply, collection: PublicCollection, form: { error?: string; displayName?: string; phone?: string; status?: number } = {}) {
  const price = amount(collection.amountPerPersonMinor);
  const org = escapeHtml(collection.org.name);
  return sendHtmlPage(
    reply,
    form.status ?? 200,
    `Pay ${collection.org.name}`,
    `<h1>Pay ${price} to ${org}</h1>
<p>${escapeHtml(collection.title)}</p>
${form.error ? `<div class="error" role="alert">${escapeHtml(form.error)}</div>` : ""}
<form method="post" action="/c/${encodeURIComponent(collection.slug)}/pay">
<label for="name">Your name</label>
<input id="name" name="displayName" required maxlength="60" autocomplete="name" value="${escapeHtml(form.displayName ?? "")}">
<label for="phone">Mobile number (optional)</label>
<input id="phone" name="phone" type="tel" inputmode="tel" autocomplete="tel" maxlength="20" value="${escapeHtml(form.phone ?? "")}">
<p class="small">Your name tells ${org} who paid. Your bank may ask for your number.</p>
<button class="primary" type="submit">Pay ${price} with your bank</button>
</form>
<p class="small">You approve the payment in your own banking app and it goes straight from your bank to theirs. Quid never holds your money.</p>`,
    { forms: true },
  );
}

export async function collectPageRoutes(app: FastifyInstance, options: { pagesPerMinute: number; paymentsPerMinute: number }): Promise<void> {
  // The page's form posts urlencoded; parsed here without a dependency.
  app.addContentTypeParser("application/x-www-form-urlencoded", { parseAs: "string" }, (_request, body, done) => {
    done(null, Object.fromEntries(new URLSearchParams(typeof body === "string" ? body : body.toString("utf8"))));
  });

  const pageLimit = app.rateLimit({ max: options.pagesPerMinute, timeWindow: "1 minute" });
  const payLimit = app.rateLimit({ max: options.paymentsPerMinute, timeWindow: "1 minute" });

  /**
   * Where the bank sends someone who paid from the page. Shows the payment's state and refreshes itself while the
   * bank is still working. Found by the provider's payment id, which only the payer's browser holds.
   */
  app.get("/c/return", { onRequest: pageLimit }, async (request, reply) => {
    const { payment_id: providerPaymentId } = z.object({ payment_id: z.string().min(1).max(128).optional() }).parse(request.query);
    const payment = providerPaymentId
      ? await prisma.payment.findUnique({
          where: { tlPaymentId: providerPaymentId },
          select: { status: true, amountMinor: true, collection: { select: { slug: true, title: true, org: { select: { name: true } } } } },
        })
      : null;
    if (!payment?.collection) {
      return sendHtmlPage(reply, 404, "Payment not found", `<h1>We couldn't find that payment</h1>
<p>If your bank says the payment went through, it has. You can close this page.</p>`);
    }
    const org = escapeHtml(payment.collection.org.name);
    const what = `${amount(payment.amountMinor)} for ${escapeHtml(payment.collection.title)}`;
    if (payment.status === "EXECUTED" || payment.status === "SETTLED") {
      return sendHtmlPage(reply, 200, "Paid", `<span class="status paid">Paid</span>
<h1>Thanks, you've paid ${org}</h1>
<p>Your bank has sent ${what}. You can close this page.</p>`);
    }
    if (payment.status === "FAILED" || payment.status === "CANCELLED") {
      return sendHtmlPage(reply, 200, "Not paid", `<span class="status failed">Not paid</span>
<h1>The payment didn't go through</h1>
<p>Nothing has been sent to ${org}.</p>
<a class="button primary" href="/c/${encodeURIComponent(payment.collection.slug)}">Try again</a>`);
    }
    return sendHtmlPage(
      reply,
      200,
      "Waiting for your bank",
      `<span class="status pending">Pending</span>
<h1>Waiting for your bank</h1>
<p>${what} to ${org}. This page updates by itself; it usually takes a few seconds.</p>`,
      { refreshSeconds: 3 },
    );
  });

  /** Title, amount and organisation name: JSON for the API, the pay page for a browser. */
  app.get("/c/:slug", { onRequest: pageLimit }, async (request, reply) => {
    const { slug } = z.object({ slug: z.string() }).parse(request.params);
    const collection = await findBySlug(slug);
    if (wantsJson(request)) {
      if (!collection) throw new HttpError(404, "collection_not_found", "We couldn't find that collection.");
      if (collection.status === "CLOSED") throw new HttpError(410, "collection_closed", "This collection is closed and isn't taking payments.");
      return { title: collection.title, amountPerPersonMinor: collection.amountPerPersonMinor, organisationName: collection.org.name };
    }
    if (!collection) return notFoundPage(reply);
    if (collection.status === "CLOSED") return closedPage(reply, collection);
    return payPage(reply, collection);
  });

  /**
   * Starts a payment for one share: JSON answers { paymentId, authorisationUrl }; the page's form is redirected
   * straight to the bank's payment page, or shown again with the problem.
   */
  app.post("/c/:slug/pay", { onRequest: payLimit }, async (request, reply) => {
    const { slug } = z.object({ slug: z.string() }).parse(request.params);
    const isForm = (request.headers["content-type"] ?? "").startsWith("application/x-www-form-urlencoded");
    const body = PayBody.parse(request.body ?? {});
    try {
      const collection = await findBySlug(slug);
      if (!collection) throw new HttpError(404, "collection_not_found", "We couldn't find that collection.");
      const displayName = (body.displayName ?? "").trim().replace(/\s+/g, " ");
      if (displayName.length === 0) throw new HttpError(400, "invalid_name", "Enter your name, so they know who paid.");
      if (visibleLength(displayName) > 60) throw new HttpError(400, "invalid_name", "Keep your name to 60 characters.");
      const rawPhone = (body.phone ?? "").trim();
      const phoneE164 = rawPhone ? normaliseUKPhone(rawPhone) : null;
      if (rawPhone && !phoneE164) throw new HttpError(400, "invalid_phone", "Enter a UK mobile number, like 07700 900123, or leave it empty.");
      const started = await createCollectionPayment(
        app.services.paymentProvider,
        { slug, payer: { kind: "link", displayName, phoneE164 } },
        request.log,
      );
      if (!started.authorisationUrl) {
        throw new HttpError(502, "payment_provider_unavailable", "We couldn't open your bank's payment page just now. Nothing has been sent; try again in a moment.");
      }
      if (isForm) return reply.redirect(started.authorisationUrl, 303);
      return reply.status(201).send({ paymentId: started.paymentId, authorisationUrl: started.authorisationUrl });
    } catch (error) {
      if (!isForm || !(error instanceof HttpError)) throw error;
      const collection = await findBySlug(slug);
      if (!collection) return notFoundPage(reply);
      if (collection.status === "CLOSED") return closedPage(reply, collection);
      return payPage(reply, collection, { error: error.message, displayName: body.displayName, phone: body.phone, status: error.statusCode });
    }
  });
}
