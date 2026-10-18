import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/app.js";
import { prisma } from "../src/lib/db.js";
import type { SmsSender } from "../src/services/sms.js";

/** Records every message so tests can read the one-time code out of it. */
export class CapturingSmsSender implements SmsSender {
  messages: { phoneE164: string; message: string }[] = [];

  async send(phoneE164: string, message: string): Promise<void> {
    this.messages.push({ phoneE164, message });
  }

  lastCode(): string {
    const last = this.messages.at(-1);
    const match = last?.message.match(/\b(\d{6})\b/);
    if (!match || !match[1]) throw new Error("no code in last message");
    return match[1];
  }
}

export interface TestContext {
  app: FastifyInstance;
  sms: CapturingSmsSender;
}

export async function createTestApp(): Promise<TestContext> {
  const sms = new CapturingSmsSender();
  const app = buildApp({ services: { smsSender: sms } });
  await app.ready();
  return { app, sms };
}

/** Empties every table so each test file starts from nothing (files run sequentially; see vitest.config.ts). */
export async function resetDatabase(): Promise<void> {
  await prisma.$transaction([
    prisma.session.deleteMany(),
    prisma.otpChallenge.deleteMany(),
    prisma.collectionMember.deleteMany(),
    prisma.payment.deleteMany(),
    prisma.collection.deleteMany(),
    prisma.orgMember.deleteMany(),
    prisma.organisation.deleteMany(),
    prisma.splitShare.deleteMany(),
    prisma.split.deleteMany(),
    prisma.paymentRequest.deleteMany(),
    prisma.bankAccount.deleteMany(),
    prisma.user.deleteMany(),
  ]);
}

/** Full OTP sign-in. Returns the bearer token and the user. */
export async function signIn(ctx: TestContext, phone: string): Promise<{ token: string; userId: string; isNew: boolean }> {
  const start = await ctx.app.inject({ method: "POST", url: "/auth/otp/start", payload: { phone } });
  if (start.statusCode !== 200) throw new Error(`otp start failed: ${start.body}`);
  const code = ctx.sms.lastCode();
  const verify = await ctx.app.inject({ method: "POST", url: "/auth/otp/verify", payload: { phone, code } });
  if (verify.statusCode !== 200) throw new Error(`otp verify failed: ${verify.body}`);
  const body = verify.json();
  return { token: body.token, userId: body.user.id, isNew: body.isNew };
}

export function bearer(token: string): Record<string, string> {
  return { authorization: `Bearer ${token}` };
}
