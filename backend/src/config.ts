import { z } from "zod";

// Load backend/.env if present (Node >= 20.12). Missing file is fine: CI and prod set real env vars.
// Tests never read it: vitest.config.ts defines their whole environment, so a developer's .env cannot leak in.
if (process.env.NODE_ENV !== "test") {
  try {
    process.loadEnvFile(".env");
  } catch {
    // no .env file — rely on the process environment
  }
}

const emptyToUndefined = (value: unknown) => (value === "" ? undefined : value);

const EnvSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default("127.0.0.1"),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"]).default("info"),
  // "1" or "true" turns on pino-pretty (a devDependency). Off by default so production starts never depend on it.
  LOG_PRETTY: z
    .preprocess(emptyToUndefined, z.enum(["0", "1", "true", "false"]).default("0"))
    .transform((value) => value === "1" || value === "true"),
  DATABASE_URL: z.string().min(1),
  PHONE_HASH_PEPPER: z.string().min(32, "PHONE_HASH_PEPPER must be at least 32 characters"),
  BANK_DATA_KEY: z
    .string()
    .regex(/^[0-9a-fA-F]{64}$/, "BANK_DATA_KEY must be 32 bytes as 64 hex characters"),
  PUBLIC_BASE_URL: z.string().url().default("http://localhost:3000"),
  // Behind ngrok or a load balancer the client address is in X-Forwarded-For. Off by default. Set a hop count ("1")
  // or a comma-separated address/CIDR list ("loopback,10.0.0.0/8"). Never "true": the leftmost header value is
  // client-controlled and would let a caller choose their own rate-limit bucket.
  TRUST_PROXY: z
    .preprocess(emptyToUndefined, z.string().optional())
    .transform((value, ctx): false | number | string[] => {
      if (value === undefined || value === "0" || value === "false") return false;
      if (value === "true") {
        ctx.addIssue({ code: "custom", message: "TRUST_PROXY must be a hop count or an address list, not true" });
        return z.NEVER;
      }
      if (/^\d+$/.test(value)) return Number(value);
      return value.split(",").map((entry) => entry.trim()).filter(Boolean);
    }),
  // Pluggable senders/verifiers (docs/SPEC.md sections 5 and 6). "log"/"fake" are dev-only and refused in production.
  SMS_SENDER: z.enum(["log", "none"]).default("log"),
  COP_VERIFIER: z.enum(["fake", "none"]).default("fake"),
  SESSION_TTL_DAYS: z.coerce.number().int().positive().default(30),
  OTP_TTL_MINUTES: z.coerce.number().int().positive().default(5),
  TRUELAYER_ENV: z.enum(["sandbox", "live"]).default("sandbox"),
  TRUELAYER_CLIENT_ID: z.preprocess(emptyToUndefined, z.string().optional()),
  TRUELAYER_CLIENT_SECRET: z.preprocess(emptyToUndefined, z.string().optional()),
  TRUELAYER_KID: z.preprocess(emptyToUndefined, z.string().optional()),
  TRUELAYER_PRIVATE_KEY_PATH: z.preprocess(emptyToUndefined, z.string().optional()),
});

export type Env = z.infer<typeof EnvSchema>;

function loadEnv(): Env {
  const parsed = EnvSchema.safeParse(process.env);
  if (!parsed.success) {
    const lines = parsed.error.issues.map((issue) => `  ${issue.path.join(".")}: ${issue.message}`);
    throw new Error(`Invalid environment configuration:\n${lines.join("\n")}\nSee backend/.env.example.`);
  }
  const config = parsed.data;
  if (config.NODE_ENV === "production") {
    // Fail closed: dev stand-ins must never ship.
    const problems: string[] = [];
    if (config.SMS_SENDER === "log") problems.push("SMS_SENDER=log logs OTP codes; set a real sender");
    if (config.COP_VERIFIER === "fake") problems.push("COP_VERIFIER=fake accepts any account; set a real verifier");
    if (config.PHONE_HASH_PEPPER.startsWith("dev-only")) problems.push("PHONE_HASH_PEPPER is the dev placeholder");
    if (/^0+$/.test(config.BANK_DATA_KEY)) problems.push("BANK_DATA_KEY is the all-zero placeholder");
    if (problems.length > 0) {
      throw new Error(`Refusing to start in production:\n${problems.map((p) => `  ${p}`).join("\n")}`);
    }
  }
  return config;
}

export const env: Env = loadEnv();

export const isProduction = env.NODE_ENV === "production";
export const isTest = env.NODE_ENV === "test";
