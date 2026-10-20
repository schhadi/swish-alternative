-- AlterTable
ALTER TABLE "Payment" ADD COLUMN "lastPolledAt" DATETIME;
ALTER TABLE "Payment" ADD COLUMN "providerId" TEXT;
ALTER TABLE "Payment" ADD COLUMN "providerStatus" TEXT;

-- CreateTable
CREATE TABLE "WebhookEvent" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "type" TEXT NOT NULL,
    "paymentId" TEXT,
    "receivedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
