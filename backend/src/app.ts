import Fastify, { type FastifyInstance } from "fastify";
import { ZodError } from "zod";
import { loggerOptions } from "./lib/logger.js";
import { healthRoutes } from "./routes/health.js";

export class HttpError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

/**
 * Builds the Fastify app without starting it, so tests can use `app.inject`.
 * Every error response has the shape { error: string, message: string, issues?: [...] }.
 */
export function buildApp(): FastifyInstance {
  const app = Fastify({ logger: loggerOptions });

  app.setErrorHandler((error: unknown, request, reply) => {
    if (error instanceof ZodError) {
      return reply.status(400).send({
        error: "validation_error",
        message: "Request failed validation",
        issues: error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message })),
      });
    }
    if (error instanceof HttpError) {
      return reply.status(error.statusCode).send({ error: error.code, message: error.message });
    }
    // Fastify's own errors (bad JSON body, payload too large, ...) carry a statusCode.
    const rawStatus = error instanceof Error ? (error as Error & { statusCode?: unknown }).statusCode : undefined;
    const statusCode = typeof rawStatus === "number" && rawStatus >= 400 ? rawStatus : 500;
    if (statusCode >= 500) {
      request.log.error({ err: error }, "unhandled error");
    }
    return reply.status(statusCode).send({
      error: statusCode >= 500 ? "internal_error" : "bad_request",
      message: statusCode >= 500 || !(error instanceof Error) ? "Something went wrong" : error.message,
    });
  });

  app.setNotFoundHandler((_request, reply) => {
    return reply.status(404).send({ error: "not_found", message: "No such route" });
  });

  app.register(healthRoutes);

  return app;
}
