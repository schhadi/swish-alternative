import rateLimit from "@fastify/rate-limit";
import Fastify, { type FastifyInstance } from "fastify";
import { ZodError } from "zod";
import { env } from "./config.js";
import { HttpError } from "./lib/errors.js";
import { loggerOptions } from "./lib/logger.js";
import { authRoutes } from "./routes/auth.js";
import { directoryRoutes } from "./routes/directory.js";
import { healthRoutes } from "./routes/health.js";
import { meRoutes } from "./routes/me.js";
import { paymentRoutes } from "./routes/payments.js";
import { placeholderRoutes } from "./routes/placeholders.js";
import { providerRoutes } from "./routes/providers.js";
import { FakePayeeVerifier, NotImplementedPayeeVerifier, type PayeeVerifier } from "./services/cop.js";
import { StaticProviderSource, type ProviderSource } from "./services/providers.js";
import { LogSmsSender, NotImplementedSmsSender, type SmsSender } from "./services/sms.js";

export { HttpError } from "./lib/errors.js";

/** Pluggable services. Tests inject capturing fakes; production wires real implementations here. */
export interface AppServices {
  smsSender: SmsSender;
  payeeVerifier: PayeeVerifier;
  providerSource: ProviderSource;
}

export interface BuildAppOptions {
  services?: Partial<AppServices>;
}

declare module "fastify" {
  interface FastifyInstance {
    services: AppServices;
  }
}

/**
 * Builds the Fastify app without starting it, so tests can use `app.inject`.
 * Every error response has the shape { error: string, message: string, details?: {...}, issues?: [...] }.
 */
export function buildApp(options: BuildAppOptions = {}): FastifyInstance {
  const app = Fastify({ logger: loggerOptions });

  const services: AppServices = {
    smsSender: options.services?.smsSender ?? (env.SMS_SENDER === "log" ? new LogSmsSender(app.log) : new NotImplementedSmsSender()),
    payeeVerifier: options.services?.payeeVerifier ?? (env.COP_VERIFIER === "fake" ? new FakePayeeVerifier() : new NotImplementedPayeeVerifier()),
    providerSource: options.services?.providerSource ?? new StaticProviderSource(),
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
  app.register(authRoutes);
  app.register(meRoutes);
  app.register(providerRoutes);
  app.register(directoryRoutes);
  app.register(paymentRoutes);
  app.register(placeholderRoutes);

  return app;
}
