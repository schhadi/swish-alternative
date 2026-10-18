import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { env } from "../config.js";
import { currentUser, requireAuth } from "../lib/auth.js";
import { prisma } from "../lib/db.js";
import { publicUser } from "../lib/dto.js";
import { HttpError } from "../lib/errors.js";
import { normaliseUKPhone } from "../lib/phone.js";
import { hashPhone } from "../lib/phoneHash.js";
import { digestsEqual, hashOtpCode, hashToken, newOtpCode, newSessionToken } from "../lib/tokens.js";
import { LIMITS } from "../limits.js";

const StartBody = z.object({ phone: z.string().min(5).max(32) });
const VerifyBody = z.object({ phone: z.string().min(5).max(32), code: z.string().regex(/^\d{6}$/, "Enter the 6-digit code") });

const perIp = { config: { rateLimit: { max: LIMITS.authRequestsPerMinutePerIp, timeWindow: "1 minute" } } };

export async function authRoutes(app: FastifyInstance): Promise<void> {
  /**
   * Starts a sign-in: creates a one-time code for the number and hands it to the SmsSender.
   * The response is identical for registered and unregistered numbers, so it cannot be used to probe the directory.
   */
  app.post("/auth/otp/start", perIp, async (request) => {
    const { phone } = StartBody.parse(request.body);
    const phoneE164 = normaliseUKPhone(phone);
    if (!phoneE164) {
      throw new HttpError(400, "invalid_phone", "Enter a UK mobile number, like 07700 900123.");
    }
    const windowStart = new Date(Date.now() - LIMITS.otpStartWindowMinutes * 60_000);
    const recent = await prisma.otpChallenge.count({ where: { phoneE164, createdAt: { gte: windowStart } } });
    if (recent >= LIMITS.otpStartsPerWindow) {
      throw new HttpError(429, "otp_rate_limited", "Too many codes requested for this number. Try again in a few minutes.");
    }
    const code = newOtpCode();
    const expiresAt = new Date(Date.now() + env.OTP_TTL_MINUTES * 60_000);
    // Only the newest code is ever valid: supersede anything still open for this number.
    await prisma.$transaction([
      prisma.otpChallenge.updateMany({ where: { phoneE164, consumedAt: null }, data: { consumedAt: new Date() } }),
      prisma.otpChallenge.create({ data: { phoneE164, codeHash: hashOtpCode(phoneE164, code), expiresAt } }),
    ]);
    try {
      await app.services.smsSender.send(phoneE164, `Your Quid code is ${code}. It expires in ${env.OTP_TTL_MINUTES} minutes.`);
    } catch (error) {
      request.log.error({ err: error }, "sms sender failed");
      throw new HttpError(503, "sms_unavailable", "We couldn't send a code right now. Try again shortly.");
    }
    return { phoneE164, expiresInSeconds: env.OTP_TTL_MINUTES * 60 };
  });

  /** Checks the code, creates the user on first sign-in, and returns a bearer token. */
  app.post("/auth/otp/verify", perIp, async (request) => {
    const { phone, code } = VerifyBody.parse(request.body);
    const phoneE164 = normaliseUKPhone(phone);
    if (!phoneE164) {
      throw new HttpError(400, "invalid_phone", "Enter a UK mobile number, like 07700 900123.");
    }
    const challenge = await prisma.otpChallenge.findFirst({
      where: { phoneE164, consumedAt: null },
      orderBy: { createdAt: "desc" },
    });
    if (!challenge) {
      throw new HttpError(400, "otp_missing", "Request a code first.");
    }
    if (challenge.attempts >= LIMITS.otpMaxAttempts) {
      throw new HttpError(429, "otp_locked", "Too many attempts. Request a new code.");
    }
    if (challenge.expiresAt.getTime() <= Date.now()) {
      throw new HttpError(400, "otp_expired", "That code has expired. Request a new one.");
    }
    if (!digestsEqual(challenge.codeHash, hashOtpCode(phoneE164, code))) {
      const updated = await prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: { attempts: { increment: 1 } },
      });
      const attemptsRemaining = Math.max(0, LIMITS.otpMaxAttempts - updated.attempts);
      if (attemptsRemaining === 0) {
        throw new HttpError(429, "otp_locked", "Too many attempts. Request a new code.", { attemptsRemaining });
      }
      throw new HttpError(400, "otp_invalid", `That code isn't right. ${attemptsRemaining} ${attemptsRemaining === 1 ? "attempt" : "attempts"} left.`, {
        attemptsRemaining,
      });
    }

    const token = newSessionToken();
    const sessionExpiresAt = new Date(Date.now() + env.SESSION_TTL_DAYS * 24 * 60 * 60_000);
    const { user, isNew } = await prisma.$transaction(async (tx) => {
      await tx.otpChallenge.updateMany({ where: { phoneE164, consumedAt: null }, data: { consumedAt: new Date() } });
      const existing = await tx.user.findUnique({ where: { phoneE164 } });
      let user = existing;
      let isNew = false;
      if (!user) {
        user = await tx.user.create({ data: { phoneE164, phoneHash: hashPhone(phoneE164), displayName: "" } });
        isNew = true;
      } else {
        user = await tx.user.update({
          where: { id: user.id },
          data: { lastSeenAt: new Date(), ...(user.phoneHash ? {} : { phoneHash: hashPhone(phoneE164) }) },
        });
      }
      await tx.session.create({ data: { userId: user.id, tokenHash: hashToken(token), expiresAt: sessionExpiresAt } });
      return { user, isNew };
    });
    request.log.info({ userId: user.id, isNew }, "signed in");
    return { token, user: publicUser(user), isNew };
  });

  /** Ends this session only. */
  app.post("/auth/logout", { preHandler: requireAuth }, async (request, reply) => {
    currentUser(request);
    if (request.sessionId) {
      await prisma.session.deleteMany({ where: { id: request.sessionId } });
    }
    return reply.status(204).send();
  });
}
