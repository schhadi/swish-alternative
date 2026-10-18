import pino from "pino";
import { describe, expect, it } from "vitest";
import { REDACT_PATHS, loggerOptions } from "../src/lib/logger.js";

function captureLogger(): { logger: pino.Logger; lines: () => Record<string, unknown>[] } {
  const chunks: string[] = [];
  // A bare object with write() is a synchronous pino destination; a Node Writable would buffer.
  const destination = {
    write(chunk: string) {
      chunks.push(chunk);
    },
  };
  const logger = pino({ ...loggerOptions, level: "info" }, destination);
  return {
    logger,
    lines: () => chunks.join("").trim().split("\n").filter(Boolean).map((line) => JSON.parse(line) as Record<string, unknown>),
  };
}

describe("logger redaction", () => {
  it("censors sensitive fields at the top level, one level deep and under req.body", () => {
    const { logger, lines } = captureLogger();
    logger.info({ phone: "+447700900123", sortCode: "123456", accountNumber: "12345678" }, "top level");
    logger.info({ user: { phone: "+447700900123", phoneE164: "+447700900123" }, session: { token: "abc" } }, "nested");
    logger.info({ req: { body: { phone: "+447700900123", code: "123456", sortCode: "123456" } } }, "request body");
    // The dev OTP line (spec section 5: "dev mode: code is logged") must stay readable.
    logger.info({ sms: { to: "+44 ***123", body: "Your Quid code is 123456" } }, "sms");
    const [top, nested, body, sms] = lines();
    expect(top).toMatchObject({ phone: "[redacted]", sortCode: "[redacted]", accountNumber: "[redacted]" });
    expect(nested).toMatchObject({ user: { phone: "[redacted]", phoneE164: "[redacted]" }, session: { token: "[redacted]" } });
    expect(body).toMatchObject({ req: { body: { phone: "[redacted]", code: "[redacted]", sortCode: "[redacted]" } } });
    expect(sms).toMatchObject({ sms: { body: "Your Quid code is 123456" } });
    expect(JSON.stringify(lines())).not.toContain("+447700900123");
  });

  it("keeps error codes visible for debugging", () => {
    const { logger, lines } = captureLogger();
    const error = Object.assign(new Error("Unique constraint failed"), { code: "P2002" });
    logger.error({ err: error }, "unhandled error");
    const [line] = lines();
    expect((line?.err as { code?: string }).code).toBe("P2002");
  });

  it("redacts the Authorization header", () => {
    const { logger, lines } = captureLogger();
    logger.info({ req: { headers: { authorization: "Bearer secret-token", host: "localhost" } } }, "req");
    const [line] = lines();
    expect((line?.req as { headers: Record<string, string> }).headers.authorization).toBe("[redacted]");
    expect((line?.req as { headers: Record<string, string> }).headers.host).toBe("localhost");
  });

  it("does not use multi-level wildcards pino cannot evaluate", () => {
    for (const path of REDACT_PATHS) {
      expect(path.split("*").length - 1).toBeLessThanOrEqual(1);
    }
  });
});
