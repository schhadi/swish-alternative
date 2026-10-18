import type { FastifyInstance } from "fastify";
import { buildApp } from "./app.js";
import { env } from "./config.js";
import { prisma } from "./lib/db.js";

let app: FastifyInstance | undefined;

async function main(): Promise<void> {
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
