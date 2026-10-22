-- AlterTable
ALTER TABLE "Collection" ADD COLUMN "closedAt" DATETIME;

-- AlterTable
ALTER TABLE "CollectionMember" ADD COLUMN "paidAt" DATETIME;

-- AlterTable
ALTER TABLE "Payment" ADD COLUMN "collectionMemberId" TEXT;

-- CreateIndex
CREATE INDEX "CollectionMember_userId_idx" ON "CollectionMember"("userId");

-- CreateIndex
CREATE INDEX "Payment_collectionMemberId_idx" ON "Payment"("collectionMemberId");

