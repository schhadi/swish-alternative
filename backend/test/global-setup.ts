import { execFileSync } from "node:child_process";

// Apply migrations to the test database before any test file runs.
export function setup(): void {
  execFileSync("npx", ["prisma", "migrate", "deploy"], {
    stdio: "inherit",
    env: { ...process.env, DATABASE_URL: "file:./test.db" },
  });
}
