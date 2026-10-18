import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);

/** Fresh test database for every `npm test`: delete the old file, then apply all migrations. */
export function setup(): void {
  const prismaDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../prisma");
  for (const suffix of ["", "-journal", "-shm", "-wal"]) {
    rmSync(path.join(prismaDir, `test.db${suffix}`), { force: true });
  }
  // Invoke the Prisma CLI through node directly: works on Windows and never falls back to a download.
  const prismaCli = require.resolve("prisma/build/index.js");
  execFileSync(process.execPath, [prismaCli, "migrate", "deploy"], {
    stdio: "inherit",
    env: { ...process.env, DATABASE_URL: "file:./test.db" },
  });
}
