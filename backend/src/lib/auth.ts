import type { FastifyReply, FastifyRequest } from "fastify";
import { prisma } from "./db.js";
import { HttpError } from "./errors.js";
import { hashToken } from "./tokens.js";

export interface AuthenticatedUser {
  id: string;
  displayName: string;
  phoneE164: string | null;
}

declare module "fastify" {
  interface FastifyRequest {
    user?: AuthenticatedUser;
    sessionId?: string;
  }
}

const LAST_USED_REFRESH_MS = 60 * 60 * 1000;

/** preHandler for bearer-authenticated routes. Sets request.user and request.sessionId or throws 401. */
export async function requireAuth(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
  const header = request.headers.authorization;
  if (typeof header !== "string" || !header.startsWith("Bearer ")) {
    throw new HttpError(401, "unauthorized", "Sign in to continue");
  }
  const token = header.slice("Bearer ".length).trim();
  if (token.length < 20) {
    throw new HttpError(401, "unauthorized", "Sign in to continue");
  }
  const session = await prisma.session.findUnique({
    where: { tokenHash: hashToken(token) },
    include: { user: { select: { id: true, displayName: true, phoneE164: true, deletedAt: true } } },
  });
  if (!session || session.expiresAt.getTime() <= Date.now() || session.user.deletedAt) {
    throw new HttpError(401, "unauthorized", "Your session has expired. Sign in again.");
  }
  if (Date.now() - session.lastUsedAt.getTime() > LAST_USED_REFRESH_MS) {
    await prisma.session.update({ where: { id: session.id }, data: { lastUsedAt: new Date() } });
  }
  request.user = { id: session.user.id, displayName: session.user.displayName, phoneE164: session.user.phoneE164 };
  request.sessionId = session.id;
}

/** Narrowing helper for handlers behind requireAuth. */
export function currentUser(request: FastifyRequest): AuthenticatedUser {
  if (!request.user) {
    throw new HttpError(401, "unauthorized", "Sign in to continue");
  }
  return request.user;
}
