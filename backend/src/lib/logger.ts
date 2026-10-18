import type { FastifyServerOptions } from "fastify";
import { env } from "../config.js";

/**
 * Pino options for Fastify's built-in logger. Use `app.log` (or a `request.log` child) everywhere;
 * services that run outside a request receive a logger as a parameter.
 * Never log account numbers, phone numbers or tokens — common field names are redacted defensively.
 */
export const loggerOptions: FastifyServerOptions["logger"] = {
  level: env.LOG_LEVEL,
  redact: {
    paths: [
      "req.headers.authorization",
      "*.sortCode",
      "*.accountNumber",
      "*.phone",
      "*.phoneE164",
      "*.token",
      "*.resourceToken",
      "*.code",
    ],
    censor: "[redacted]",
  },
  ...(env.NODE_ENV === "development"
    ? { transport: { target: "pino-pretty", options: { colorize: true, translateTime: "HH:MM:ss" } } }
    : {}),
};
