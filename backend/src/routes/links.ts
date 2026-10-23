import { randomInt } from "node:crypto";
import { Prisma } from "@prisma/client";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { env } from "../config.js";
import { currentUser, requireAuth } from "../lib/auth.js";
import { prisma } from "../lib/db.js";
import { HttpError } from "../lib/errors.js";
import { escapeHtml, firstName, sendHtmlPage } from "../lib/html.js";
import { LIMITS } from "../limits.js";

/** No look-alike characters (0/o, 1/l/i), so a code read aloud or retyped still works. */
const INVITE_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789";
const INVITE_CODE_LENGTH = 8;
const INVITE_CODE = new RegExp(`^[${INVITE_ALPHABET}]{${INVITE_CODE_LENGTH}}$`);
export const INVITE_MESSAGE = "I'm using Quid to pay friends by phone number. Join me:";

function newInviteCode(): string {
  return Array.from({ length: INVITE_CODE_LENGTH }, () => INVITE_ALPHABET[randomInt(INVITE_ALPHABET.length)]).join("");
}

function baseUrl(): string {
  return env.PUBLIC_BASE_URL.replace(/\/$/, "");
}

function downloadBlock(inviterFirstName: string | null): string {
  if (env.APP_DOWNLOAD_URL) {
    return `<a class="button secondary" href="${escapeHtml(env.APP_DOWNLOAD_URL)}">Get Quid</a>`;
  }
  const who = inviterFirstName ? escapeHtml(inviterFirstName) : "whoever sent you this link";
  return `<p class="small">Quid is in testing and not in the App Store yet. Ask ${who} how to join.</p>`;
}

/**
 * Invite links for contacts who are not on Quid (Phase 3) and the page behind a split's shared link. Both pages show
 * the sender's first name and nothing else about anyone: no surnames, numbers, amounts or other people's names.
 */
export async function linkRoutes(app: FastifyInstance, options: { appleAppIds?: readonly string[] } = {}): Promise<void> {
  const pageLimit = app.rateLimit({ max: LIMITS.publicPagesPerMinutePerIp, timeWindow: "1 minute" });
  const association = appSiteAssociation(options.appleAppIds ?? []);

  /**
   * Universal links (docs/DECISIONS.md #94): iOS fetches this once per install to learn that split links open the app.
   * Only /s/ is claimed. Invite links and collection pages stay in the browser: the people they are for may not have
   * the app, and the collection page is how anyone pays without it.
   */
  app.get("/.well-known/apple-app-site-association", async (_request, reply) => {
    if (!association) {
      throw new HttpError(404, "not_found", "Universal links are not configured.");
    }
    return reply.header("cache-control", "public, max-age=3600").type("application/json").send(association);
  });

  /** The signed-in user's invite link, created on first use and stable afterwards. */
  app.get("/me/invite", { preHandler: requireAuth }, async (request) => {
    const { id } = currentUser(request);
    let code = (await prisma.user.findUniqueOrThrow({ where: { id }, select: { inviteCode: true } })).inviteCode;
    for (let attempt = 0; !code && attempt < 5; attempt += 1) {
      try {
        await prisma.user.updateMany({ where: { id, inviteCode: null }, data: { inviteCode: newInviteCode() } });
      } catch (error) {
        // Another user already has this code: draw again.
        if (!(error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002")) throw error;
      }
      code = (await prisma.user.findUniqueOrThrow({ where: { id }, select: { inviteCode: true } })).inviteCode;
    }
    if (!code) throw new Error("could not allocate an invite code");
    return { code, url: `${baseUrl()}/i/${code}`, message: INVITE_MESSAGE };
  });

  app.get("/i/:code", { onRequest: pageLimit }, async (request, reply) => {
    const { code } = z.object({ code: z.string() }).parse(request.params);
    const inviter = INVITE_CODE.test(code)
      ? await prisma.user.findUnique({ where: { inviteCode: code }, select: { displayName: true, deletedAt: true } })
      : null;
    if (!inviter || inviter.deletedAt || inviter.displayName === "") {
      return sendHtmlPage(reply, 404, "Invite not found", `<h1>This invite link isn't valid</h1>
<p>It may have been mistyped. Ask the person who sent it for a new one.</p>
${downloadBlock(null)}`);
    }
    const name = firstName(inviter.displayName);
    return sendHtmlPage(reply, 200, `Join ${name} on Quid`, `<h1>${escapeHtml(name)} invited you to Quid</h1>
<p>Quid lets you pay friends by picking them from your contacts. Every payment goes from your bank to theirs and you approve it in your own banking app. Quid never holds your money.</p>
${downloadBlock(name)}`);
  });

  /** A split's shared link: hands over to the app, which shows the visitor their own share. */
  app.get("/s/:id", { onRequest: pageLimit }, async (request, reply) => {
    const { id } = z.object({ id: z.string() }).parse(request.params);
    const split = z.string().uuid().safeParse(id).success
      ? await prisma.split.findUnique({ where: { id }, select: { id: true, title: true, creator: { select: { displayName: true, deletedAt: true } } } })
      : null;
    if (!split || split.creator.deletedAt) {
      return sendHtmlPage(reply, 404, "Split not found", `<h1>This link isn't valid</h1>
<p>It may have been mistyped, or the split was removed.</p>`);
    }
    const name = firstName(split.creator.displayName);
    return sendHtmlPage(reply, 200, `${name}'s split on Quid`, `<h1>${escapeHtml(name)} is splitting “${escapeHtml(split.title)}” on Quid</h1>
<p>Open Quid to see your share and pay it from your banking app.</p>
<a class="button primary" href="quid://split/${encodeURIComponent(split.id)}">Open in Quid</a>
${downloadBlock(name)}`);
  });
}

/** The apple-app-site-association document, or null when no app id is configured. */
export function appSiteAssociation(appIds: readonly string[]) {
  if (appIds.length === 0) return null;
  return {
    applinks: {
      details: [
        {
          appIDs: [...appIds],
          components: [{ "/": "/s/*", comment: "A split's shared link opens the split in Quid" }],
        },
      ],
    },
  };
}
