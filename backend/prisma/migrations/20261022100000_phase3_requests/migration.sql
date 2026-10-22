-- AlterTable
ALTER TABLE "User" ADD COLUMN "inviteCode" TEXT;

-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_PaymentRequest" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "requesterUserId" TEXT NOT NULL,
    "payerUserId" TEXT NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "reference" TEXT NOT NULL,
    "note" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "paymentId" TEXT,
    "expiresAt" DATETIME NOT NULL,
    "lastRemindedAt" DATETIME,
    "remindCount" INTEGER NOT NULL DEFAULT 0,
    "paidAt" DATETIME,
    "declinedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PaymentRequest_requesterUserId_fkey" FOREIGN KEY ("requesterUserId") REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "PaymentRequest_payerUserId_fkey" FOREIGN KEY ("payerUserId") REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "PaymentRequest_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "Payment" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);
INSERT INTO "new_PaymentRequest" ("amountMinor", "createdAt", "expiresAt", "id", "lastRemindedAt", "note", "payerUserId", "paymentId", "reference", "requesterUserId", "status") SELECT "amountMinor", "createdAt", "expiresAt", "id", "lastRemindedAt", "note", "payerUserId", "paymentId", "reference", "requesterUserId", "status" FROM "PaymentRequest";
DROP TABLE "PaymentRequest";
ALTER TABLE "new_PaymentRequest" RENAME TO "PaymentRequest";
CREATE UNIQUE INDEX "PaymentRequest_paymentId_key" ON "PaymentRequest"("paymentId");
CREATE INDEX "PaymentRequest_payerUserId_status_idx" ON "PaymentRequest"("payerUserId", "status");
CREATE INDEX "PaymentRequest_requesterUserId_createdAt_idx" ON "PaymentRequest"("requesterUserId", "createdAt");
CREATE INDEX "PaymentRequest_status_expiresAt_idx" ON "PaymentRequest"("status", "expiresAt");
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;

-- CreateIndex
CREATE UNIQUE INDEX "User_inviteCode_key" ON "User"("inviteCode");

