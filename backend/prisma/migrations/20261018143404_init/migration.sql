-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "phoneE164" TEXT,
    "phoneHash" TEXT,
    "displayName" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deletedAt" DATETIME
);

-- CreateTable
CREATE TABLE "BankAccount" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT,
    "sortCodeEnc" TEXT NOT NULL,
    "accountNumberEnc" TEXT NOT NULL,
    "accountHolderNameEnc" TEXT NOT NULL,
    "providerId" TEXT,
    "copStatus" TEXT NOT NULL DEFAULT 'UNCHECKED',
    "verifiedAt" DATETIME,
    "changedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "BankAccount_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "Session" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" DATETIME NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastUsedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Session_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "OtpChallenge" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "phoneE164" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "expiresAt" DATETIME NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "consumedAt" DATETIME,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateTable
CREATE TABLE "Payment" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "payerUserId" TEXT,
    "payerDisplayName" TEXT,
    "payeeUserId" TEXT,
    "collectionId" TEXT,
    "requestId" TEXT,
    "amountMinor" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'GBP',
    "reference" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'CREATED',
    "tlPaymentId" TEXT,
    "failureReason" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "settledAt" DATETIME,
    CONSTRAINT "Payment_payerUserId_fkey" FOREIGN KEY ("payerUserId") REFERENCES "User" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "Payment_payeeUserId_fkey" FOREIGN KEY ("payeeUserId") REFERENCES "User" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "Payment_collectionId_fkey" FOREIGN KEY ("collectionId") REFERENCES "Collection" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "PaymentRequest" (
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
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PaymentRequest_requesterUserId_fkey" FOREIGN KEY ("requesterUserId") REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "PaymentRequest_payerUserId_fkey" FOREIGN KEY ("payerUserId") REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "PaymentRequest_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "Payment" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "Split" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "creatorUserId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "totalMinor" INTEGER NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Split_creatorUserId_fkey" FOREIGN KEY ("creatorUserId") REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "SplitShare" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "splitId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "requestId" TEXT NOT NULL,
    CONSTRAINT "SplitShare_splitId_fkey" FOREIGN KEY ("splitId") REFERENCES "Split" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "SplitShare_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "SplitShare_requestId_fkey" FOREIGN KEY ("requestId") REFERENCES "PaymentRequest" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "Organisation" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "bankAccountId" TEXT NOT NULL,
    "createdByUserId" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Organisation_bankAccountId_fkey" FOREIGN KEY ("bankAccountId") REFERENCES "BankAccount" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "Organisation_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "OrgMember" (
    "orgId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'MEMBER',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY ("orgId", "userId"),
    CONSTRAINT "OrgMember_orgId_fkey" FOREIGN KEY ("orgId") REFERENCES "Organisation" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "OrgMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "Collection" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "orgId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "amountPerPersonMinor" INTEGER NOT NULL,
    "dueAt" DATETIME,
    "slug" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'OPEN',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Collection_orgId_fkey" FOREIGN KEY ("orgId") REFERENCES "Organisation" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "CollectionMember" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "collectionId" TEXT NOT NULL,
    "userId" TEXT,
    "displayName" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'UNPAID',
    "paymentId" TEXT,
    "remindedAt" DATETIME,
    "remindCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "CollectionMember_collectionId_fkey" FOREIGN KEY ("collectionId") REFERENCES "Collection" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "CollectionMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "CollectionMember_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "Payment" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateIndex
CREATE UNIQUE INDEX "User_phoneE164_key" ON "User"("phoneE164");

-- CreateIndex
CREATE UNIQUE INDEX "User_phoneHash_key" ON "User"("phoneHash");

-- CreateIndex
CREATE UNIQUE INDEX "BankAccount_userId_key" ON "BankAccount"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "Session_tokenHash_key" ON "Session"("tokenHash");

-- CreateIndex
CREATE INDEX "Session_userId_idx" ON "Session"("userId");

-- CreateIndex
CREATE INDEX "OtpChallenge_phoneE164_createdAt_idx" ON "OtpChallenge"("phoneE164", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Payment_tlPaymentId_key" ON "Payment"("tlPaymentId");

-- CreateIndex
CREATE INDEX "Payment_payerUserId_createdAt_idx" ON "Payment"("payerUserId", "createdAt");

-- CreateIndex
CREATE INDEX "Payment_payeeUserId_createdAt_idx" ON "Payment"("payeeUserId", "createdAt");

-- CreateIndex
CREATE INDEX "Payment_collectionId_idx" ON "Payment"("collectionId");

-- CreateIndex
CREATE INDEX "Payment_status_updatedAt_idx" ON "Payment"("status", "updatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "PaymentRequest_paymentId_key" ON "PaymentRequest"("paymentId");

-- CreateIndex
CREATE INDEX "PaymentRequest_payerUserId_status_idx" ON "PaymentRequest"("payerUserId", "status");

-- CreateIndex
CREATE INDEX "PaymentRequest_requesterUserId_createdAt_idx" ON "PaymentRequest"("requesterUserId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "SplitShare_requestId_key" ON "SplitShare"("requestId");

-- CreateIndex
CREATE INDEX "SplitShare_splitId_idx" ON "SplitShare"("splitId");

-- CreateIndex
CREATE UNIQUE INDEX "Collection_slug_key" ON "Collection"("slug");

-- CreateIndex
CREATE UNIQUE INDEX "CollectionMember_paymentId_key" ON "CollectionMember"("paymentId");

-- CreateIndex
CREATE INDEX "CollectionMember_collectionId_status_idx" ON "CollectionMember"("collectionId", "status");
