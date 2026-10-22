import rateLimit from "@fastify/rate-limit";
import Fastify, { type FastifyInstance } from "fastify";
import { ZodError } from "zod";
import { env, truelayerHosts } from "./config.js";
import { HttpError } from "./lib/errors.js";
import { loggerOptions } from "./lib/logger.js";
import { LIMITS } from "./limits.js";
import { readFileSync } from "node:fs";
import { authRoutes } from "./routes/auth.js";
import { collectPageRoutes } from "./routes/collectPage.js";
import { devRoutes } from "./routes/dev.js";
import { directoryRoutes } from "./routes/directory.js";
import { healthRoutes } from "./routes/health.js";
import { linkRoutes } from "./routes/links.js";
import { meRoutes } from "./routes/me.js";
import { organisationRoutes } from "./routes/orgs.js";
import { paymentRoutes } from "./routes/payments.js";
import { providerRoutes } from "./routes/providers.js";
import { requestRoutes } from "./routes/requests.js";
import { webhookRoutes } from "./routes/webhooks.js";
import { FakePayeeVerifier, NotImplementedPayeeVerifier, type PayeeVerifier } from "./services/cop.js";
import { FakePaymentProvider } from "./services/payments/fake.js";
import type { PaymentProvider } from "./services/payments/provider.js";
import { StaticProviderSource, type ProviderSource } from "./services/providers.js";
import { TrueLayerClient } from "./services/truelayer/client.js";
import { TrueLayerWebhookVerifier, type WebhookVerifier } from "./services/truelayer/webhooks.js";
import { LogSmsSender, NotImplementedSmsSender, type SmsSender } from "./services/sms.js";

export { HttpError } from "./lib/errors.js";

/** Pluggable services. Tests inject capturing fakes; production wires real implementations here. */
export interface AppServices {
  smsSender: SmsSender;
  payeeVerifier: PayeeVerifier;
  providerSource: ProviderSource;
  paymentProvider: PaymentProvider;
  webhookVerifier: WebhookVerifier;
}

export interface BuildAppOptions {
  services?: Partial<AppServices>;
  /**
   * Per-IP cap on the auth routes (default LIMITS.authRequestsPerMinutePerIp). The one limit tests can tune:
   * every injected request shares 127.0.0.1, so a file of tests would trip the production cap.
   */
  authRequestsPerMinutePerIp?: number;
  /** Per-IP caps on the public collection page and on payments started from it; tunable for the same reason. */
  publicPagesPerMinutePerIp?: number;
  publicPaymentsPerMinutePerIp?: number;
  /** Fastify's trustProxy (default env.TRUST_PROXY). Tests set it to prove per-IP limits key on X-Forwarded-For. */
  trustProxy?: boolean | number | string | string[];
}

/** PAYMENT_PROVIDER=truelayer needs the Console credentials and the signing key; fail at startup, not at the first payment. */
function buildTrueLayerClient(): TrueLayerClient {
  const missing = (["TRUELAYER_CLIENT_ID", "TRUELAYER_CLIENT_SECRET", "TRUELAYER_KID", "TRUELAYER_PRIVATE_KEY_PATH"] as const).filter((key) => !env[key]);
  if (missing.length > 0) {
    throw new Error(`PAYMENT_PROVIDER=truelayer needs ${missing.join(", ")} in backend/.env`);
  }
  const hosts = truelayerHosts();
  return new TrueLayerClient({
    apiBaseUrl: hosts.apiBaseUrl,
    authBaseUrl: hosts.authBaseUrl,
    hppBaseUrl: hosts.hppBaseUrl,
    clientId: env.TRUELAYER_CLIENT_ID as string,
    clientSecret: env.TRUELAYER_CLIENT_SECRET as string,
    kid: env.TRUELAYER_KID as string,
    privateKeyPem: readFileSync(env.TRUELAYER_PRIVATE_KEY_PATH as string, "utf8"),
  });
}

declare module "fastify" {
  interface FastifyInstance {
    services: AppServices;
  }
}

/** Fastify's typings leave out the hop-count form that its runtime accepts, so a number becomes the equivalent function. */
function trustProxySetting(value: boolean | number | string | string[]): boolean | string | string[] | ((address: string, hop: number) => boolean) {
  if (typeof value === "number") {
    return (_address: string, hop: number) => hop < value;
  }
  return value;
}

/**
 * Builds the Fastify app without starting it, so tests can use `app.inject`.
 * Every error response has the shape { error: string, message: string, details?: {...}, issues?: [...] }.
 */
export function buildApp(options: BuildAppOptions = {}): FastifyInstance {
  const app = Fastify({ logger: loggerOptions, trustProxy: trustProxySetting(options.trustProxy ?? env.TRUST_PROXY) });

  const services: AppServices = {
    smsSender: options.services?.smsSender ?? (env.SMS_SENDER === "log" ? new LogSmsSender(app.log) : new NotImplementedSmsSender()),
    payeeVerifier: options.services?.payeeVerifier ?? (env.COP_VERIFIER === "fake" ? new FakePayeeVerifier() : new NotImplementedPayeeVerifier()),
    providerSource: options.services?.providerSource ?? new StaticProviderSource(),
    paymentProvider:
      options.services?.paymentProvider ?? (env.PAYMENT_PROVIDER === "truelayer" ? buildTrueLayerClient() : new FakePaymentProvider(env.PUBLIC_BASE_URL)),
    webhookVerifier: options.services?.webhookVerifier ?? new TrueLayerWebhookVerifier(truelayerHosts().webhookJkus),
  };
  app.decorate("services", services);

  app.setErrorHandler((error: unknown, request, reply) => {
    if (error instanceof ZodError) {
      return reply.status(400).send({
        error: "validation_error",
        message: "Request failed validation",
        issues: error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message })),
      });
    }
    if (error instanceof HttpError) {
      return reply
        .status(error.statusCode)
        .send({ error: error.code, message: error.message, ...(error.details ? { details: error.details } : {}) });
    }
    // Fastify's own errors (bad JSON body, payload too large, rate limit, ...) carry a statusCode.
    const rawStatus = error instanceof Error ? (error as Error & { statusCode?: unknown }).statusCode : undefined;
    const statusCode = typeof rawStatus === "number" && rawStatus >= 400 ? rawStatus : 500;
    if (statusCode >= 500) {
      request.log.error({ err: error }, "unhandled error");
    }
    const code = statusCode === 429 ? "rate_limited" : statusCode >= 500 ? "internal_error" : "bad_request";
    return reply.status(statusCode).send({
      error: code,
      message: statusCode >= 500 || !(error instanceof Error) ? "Something went wrong" : error.message,
    });
  });

  app.setNotFoundHandler((_request, reply) => {
    return reply.status(404).send({ error: "not_found", message: "No such route" });
  });

  // Opt-in per route via `config: { rateLimit: {...} }`; see docs/SPEC.md section 7.
  app.register(rateLimit, { global: false });

  app.register(healthRoutes);
  app.register(authRoutes, { perIpMax: options.authRequestsPerMinutePerIp ?? LIMITS.authRequestsPerMinutePerIp });
  app.register(meRoutes);
  app.register(providerRoutes);
  app.register(directoryRoutes);
  app.register(paymentRoutes);
  app.register(requestRoutes);
  app.register(linkRoutes);
  app.register(organisationRoutes);
  app.register(collectPageRoutes, {
    pagesPerMinute: options.publicPagesPerMinutePerIp ?? LIMITS.publicPagesPerMinutePerIp,
    paymentsPerMinute: options.publicPaymentsPerMinutePerIp ?? LIMITS.publicPaymentsPerMinutePerIp,
  });
  app.register(webhookRoutes);
  if (services.paymentProvider instanceof FakePaymentProvider) {
    app.register(devRoutes, { provider: services.paymentProvider, returnUri: env.PAYMENT_RETURN_URI });
  }

  return app;
}
