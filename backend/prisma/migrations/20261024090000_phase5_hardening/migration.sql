-- Phase 5: requests the requester withdrew, and which payments disclosed a new payee's bank-held name.
-- RequestStatus gains CANCELLED (a TEXT column on SQLite, so no SQL for the enum itself).

-- AlterTable
ALTER TABLE "PaymentRequest" ADD COLUMN "cancelledAt" DATETIME;

-- AlterTable
ALTER TABLE "Payment" ADD COLUMN "firstTimePayee" BOOLEAN NOT NULL DEFAULT false;
