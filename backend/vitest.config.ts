import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["test/**/*.test.ts"],
    globalSetup: ["./test/global-setup.ts"],
    // Test-only environment. The SQLite file lives next to prisma/schema.prisma.
    env: {
      NODE_ENV: "test",
      LOG_LEVEL: "silent",
      DATABASE_URL: "file:./test.db",
      PHONE_HASH_PEPPER: "test-pepper-test-pepper-test-pepper-0123456789",
      BANK_DATA_KEY: "1111111111111111111111111111111111111111111111111111111111111111",
      PUBLIC_BASE_URL: "http://localhost:3000",
    },
  },
});
