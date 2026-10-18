import type { FastifyInstance } from "fastify";
import { prisma } from "./lib/db.js";

let app: FastifyInstance | undefined;

/**
 * Everything that can fail at startup (environment validation, logger transport, app construction, listen)
 * happens inside main(), so one handler reports it. The imports are dynamic for that reason.
 */
async function main(): Promise<void> {
  const { env } = await import("./config.js");
  const { buildApp } = await import("./app.js");
  app = buildApp();
  await app.listen({ port: env.PORT, host: env.HOST });
  app.log.info({ env: env.NODE_ENV, truelayer: env.TRUELAYER_ENV }, "quid backend ready");
}

async function shutdown(signal: string): Promise<void> {
  app?.log.info({ signal }, "shutting down");
  await app?.close();
  await prisma.$disconnect();
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
