import type { FastifyInstance } from "fastify";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildApp, type BuildAppOptions } from "../src/app.js";
import { prisma } from "../src/lib/db.js";
import { FakePaymentProvider } from "../src/services/payments/fake.js";
import type { SmsSender } from "../src/services/sms.js";
import { StaticJwksWebhookVerifier } from "../src/services/truelayer/webhooks.js";

export const FIXTURES = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "fixtures/truelayer");

export function fixture(name: string): string {
  return readFileSync(path.join(FIXTURES, name), "utf8");
}

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
  provider: FakePaymentProvider;
}

/** One app per test file. The per-IP auth cap is lifted because every injected request comes from 127.0.0.1. */
export async function createTestApp(options: BuildAppOptions = {}): Promise<TestContext> {
  const sms = new CapturingSmsSender();
  const provider = new FakePaymentProvider("http://localhost:3000");
  const app = buildApp({
    ...options,
    services: {
      smsSender: sms,
      paymentProvider: provider,
      // The official test JWKS, with the jku check off so tests can sign events with the matching test key.
      webhookVerifier: new StaticJwksWebhookVerifier(fixture("jwks.json")),
      ...options.services,
    },
    authRequestsPerMinutePerIp: options.authRequestsPerMinutePerIp ?? 10_000,
    publicPagesPerMinutePerIp: options.publicPagesPerMinutePerIp ?? 10_000,
    publicPaymentsPerMinutePerIp: options.publicPaymentsPerMinutePerIp ?? 10_000,
  });
  await app.ready();
  return { app, sms, provider };
}

/** Empties every table so each test file starts from nothing (files run sequentially; see vitest.config.ts). */
export async function resetDatabase(): Promise<void> {
  await prisma.$transaction([
    prisma.webhookEvent.deleteMany(),
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

/** Links a MATCH bank account through the API, exactly as the app does. */
export async function linkBank(ctx: TestContext, token: string, overrides: Partial<{ sortCode: string; accountNumber: string; accountHolderName: string; providerId: string }> = {}): Promise<void> {
  const payload = { sortCode: "04-00-04", accountNumber: "12345678", accountHolderName: "Sam Okafor", providerId: "ob-monzo", ...overrides };
  const response = await ctx.app.inject({ method: "PUT", url: "/me/bank-account", headers: bearer(token), payload });
  if (response.statusCode !== 200 || response.json().copStatus !== "MATCH") throw new Error(`bank link failed: ${response.body}`);
}

/** Signs in, sets a name and (optionally) links a verified account. The common setup of the Phase 3 tests. */
export async function registerUser(
  ctx: TestContext,
  phone: string,
  displayName: string,
  bank: Partial<{ sortCode: string; accountNumber: string; accountHolderName: string; providerId: string }> | null = {},
): Promise<{ token: string; userId: string }> {
  const { token, userId } = await signIn(ctx, phone);
  const named = await ctx.app.inject({ method: "PUT", url: "/me", headers: bearer(token), payload: { displayName } });
  if (named.statusCode !== 200) throw new Error(`naming failed: ${named.body}`);
  if (bank) await linkBank(ctx, token, { accountHolderName: displayName, ...bank });
  return { token, userId };
}

/** A logger that drops everything, for calling services directly. */
export const silentLog = {
  info: () => undefined,
  warn: () => undefined,
  error: () => undefined,
  debug: () => undefined,
  trace: () => undefined,
  fatal: () => undefined,
  child: () => silentLog,
  level: "silent",
  silent: () => undefined,
} as unknown as import("fastify").FastifyBaseLogger;
