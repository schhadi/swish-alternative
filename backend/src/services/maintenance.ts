import { prisma } from "../lib/db.js";

const OTP_GRACE_MS = 60 * 60 * 1000;

/**
 * Removes rows that only hold expired secrets: one-time-code challenges an hour past expiry (they contain a phone
 * number) and sessions past their TTL. Runs at startup and hourly; safe to call any time.
 */
export async function purgeExpired(now: Date = new Date()): Promise<{ challenges: number; sessions: number }> {
  const [challenges, sessions] = await prisma.$transaction([
    prisma.otpChallenge.deleteMany({ where: { expiresAt: { lt: new Date(now.getTime() - OTP_GRACE_MS) } } }),
    prisma.session.deleteMany({ where: { expiresAt: { lt: now } } }),
  ]);
  return { challenges: challenges.count, sessions: sessions.count };
}
