import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["test/**/*.test.ts"],
    // One SQLite test database, so run test files one at a time (tests within a file still share it).
    fileParallelism: false,
    globalSetup: ["./test/global-setup.ts"],
    // Test-only environment. The SQLite file lives next to prisma/schema.prisma. CI's Postgres job sets
    // QUID_TEST_DATABASE_URL (with the schema's provider switched to postgresql) to run the same suite there.
    env: {
      NODE_ENV: "test",
      LOG_LEVEL: "silent",
      LOG_PRETTY: "0",
      DATABASE_URL: process.env.QUID_TEST_DATABASE_URL ?? "file:./test.db",
      PHONE_HASH_PEPPER: "test-pepper-test-pepper-test-pepper-0123456789",
      BANK_DATA_KEY: "1111111111111111111111111111111111111111111111111111111111111111",
      PUBLIC_BASE_URL: "http://localhost:3000",
    },
  },
});
