import type { FastifyInstance } from "fastify";
import type { PrismaClient } from "@prisma/client";

let app: FastifyInstance | undefined;
let prisma: PrismaClient | undefined;

/**
 * Everything that can fail at startup (environment validation, Prisma Client construction, logger transport,
 * app construction, listen) happens inside main(), in that order, so one handler reports it.
 * The imports are dynamic for that reason: config.js must be evaluated before lib/db.js instantiates Prisma.
 */
async function main(): Promise<void> {
  const { env } = await import("./config.js");
  const db = await import("./lib/db.js");
  prisma = db.prisma;
  const { buildApp } = await import("./app.js");
  const { purgeExpired } = await import("./services/maintenance.js");
  const { expireStaleRequests } = await import("./services/requests/service.js");
  const { pollInFlightPayments } = await import("./services/payments/poller.js");
  const { LIMITS } = await import("./limits.js");
  app = buildApp();
  await app.listen({ port: env.PORT, host: env.HOST });
  app.log.info({ env: env.NODE_ENV, truelayer: env.TRUELAYER_ENV }, "quid backend ready");

  const purge = async () => {
    try {
      const removed = await purgeExpired();
      app?.log.debug(removed, "purged expired rows");
      const expired = await expireStaleRequests();
      if (expired > 0) app?.log.info({ expired }, "expired payment requests");
    } catch (error) {
      app?.log.warn({ err: error }, "purge failed");
    }
  };
  await purge();
  setInterval(() => void purge(), 60 * 60 * 1000).unref();

  // Fallback for payments whose webhook never arrived (docs/SPEC.md section 3).
  const poll = async () => {
    try {
      const result = await pollInFlightPayments(app!.services.paymentProvider, app!.log);
      if (result.checked > 0) app?.log.info(result, "polled in-flight payments");
    } catch (error) {
      app?.log.warn({ err: error }, "payment poll failed");
    }
  };
  setInterval(() => void poll(), LIMITS.pollIntervalSeconds * 1000).unref();
}

async function shutdown(signal: string): Promise<void> {
  app?.log.info({ signal }, "shutting down");
  await app?.close();
  await prisma?.$disconnect();
  process.exit(0);
}

process.on("SIGINT", () => void shutdown("SIGINT"));
process.on("SIGTERM", () => void shutdown("SIGTERM"));

main().catch((error: unknown) => {
  // The logger may not exist yet (bad env, missing transport), so fall back to stderr.
  const message = error instanceof Error ? error.stack ?? error.message : String(error);
  console.error(`[quid-backend] failed to start\n${message}`);
  process.exit(1);
});
