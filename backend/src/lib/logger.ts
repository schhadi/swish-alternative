import type { LoggerOptions } from "pino";
import { env } from "../config.js";

/**
 * Field names that must never reach a log line (docs/SPEC.md section 7). Redacted at the top level,
 * one level deep (`user.phone`, `body.sortCode`) and under `req.body`. pino's `*` matches exactly one level,
 * so deeper shapes must be redacted explicitly below — add a path here when you log a new shape.
 * `err.code` is deliberately NOT redacted: operators need P2002 / ECONNREFUSED / FST_ERR_* to debug a 500.
 */
export const SENSITIVE_FIELDS = [
  "phone",
  "phoneE164",
  "sortCode",
  "accountNumber",
  "accountHolderName",
  "token",
  "resourceToken",
  "otpCode",
] as const;

export const REDACT_PATHS: string[] = [
  "req.headers.authorization",
  "req.headers.cookie",
  "otp.code",
  "req.body.code",
  ...SENSITIVE_FIELDS.flatMap((field) => [field, `*.${field}`, `req.body.${field}`]),
];

/**
 * Pino options for Fastify's built-in logger. Use `app.log` (or a `request.log` child) everywhere;
 * services that run outside a request receive a logger as a parameter.
 * Pretty printing is an explicit opt-in (LOG_PRETTY=1) because pino-pretty is a devDependency.
 */
export const loggerOptions: LoggerOptions = {
  level: env.LOG_LEVEL,
  redact: {
    paths: REDACT_PATHS,
    censor: "[redacted]",
  },
  ...(env.LOG_PRETTY
    ? { transport: { target: "pino-pretty", options: { colorize: true, translateTime: "HH:MM:ss" } } }
    : {}),
};
