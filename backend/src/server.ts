import { buildApp } from "./app.js";
import { env } from "./config.js";
import { prisma } from "./lib/db.js";

const app = buildApp();

async function main(): Promise<void> {
  await app.listen({ port: env.PORT, host: env.HOST });
  app.log.info({ env: env.NODE_ENV, truelayer: env.TRUELAYER_ENV }, "quid backend ready");
}

async function shutdown(signal: string): Promise<void> {
  app.log.info({ signal }, "shutting down");
  await app.close();
  await prisma.$disconnect();
  process.exit(0);
}

process.on("SIGINT", () => void shutdown("SIGINT"));
process.on("SIGTERM", () => void shutdown("SIGTERM"));

main().catch((error) => {
  app.log.fatal({ err: error }, "failed to start");
  process.exit(1);
});
