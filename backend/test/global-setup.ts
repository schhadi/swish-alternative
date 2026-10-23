import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);

/**
 * Fresh test database for every `npm test`: delete the old file, then apply all migrations. With QUID_TEST_DATABASE_URL
 * (CI's Postgres job, after scripts/use-postgres.sh) the Postgres migrations are applied to that database instead; it
 * should be a new, empty database (each test file empties the tables it uses, so a rerun needs no reset).
 */
export function setup(): void {
  // Invoke the Prisma CLI through node directly: works on Windows and never falls back to a download.
  const prismaCli = require.resolve("prisma/build/index.js");
  const external = process.env.QUID_TEST_DATABASE_URL;
  if (external) {
    execFileSync(process.execPath, [prismaCli, "migrate", "deploy"], {
      stdio: "inherit",
      env: { ...process.env, DATABASE_URL: external },
    });
    return;
  }
  const prismaDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../prisma");
  for (const suffix of ["", "-journal", "-shm", "-wal"]) {
    rmSync(path.join(prismaDir, `test.db${suffix}`), { force: true });
  }
  execFileSync(process.execPath, [prismaCli, "migrate", "deploy"], {
    stdio: "inherit",
    env: { ...process.env, DATABASE_URL: "file:./test.db" },
  });
}
