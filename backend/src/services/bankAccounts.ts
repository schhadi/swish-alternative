import type { BankAccount } from "@prisma/client";
import { decryptField, encryptField } from "../lib/crypto.js";
import { prisma } from "../lib/db.js";
import { LIMITS } from "../limits.js";

/**
 * The only module that encrypts or decrypts bank details besides payment creation (Phase 2).
 * Plaintext never leaves these functions except as the comparison result below.
 */
export interface BankDetails {
  sortCode: string;
  accountNumber: string;
  accountHolderName: string;
  providerId: string | null;
}

type EncryptedColumns = Pick<BankAccount, "sortCodeEnc" | "accountNumberEnc" | "accountHolderNameEnc">;

function aad(ownerKey: string, field: keyof EncryptedColumns): string {
  return `${ownerKey}:${field}`;
}

export function encryptBankDetails(ownerKey: string, details: BankDetails): EncryptedColumns {
  return {
    sortCodeEnc: encryptField(details.sortCode, aad(ownerKey, "sortCodeEnc")),
    accountNumberEnc: encryptField(details.accountNumber, aad(ownerKey, "accountNumberEnc")),
    accountHolderNameEnc: encryptField(details.accountHolderName, aad(ownerKey, "accountHolderNameEnc")),
  };
}

export function decryptBankDetails(ownerKey: string, row: EncryptedColumns): Omit<BankDetails, "providerId"> {
  return {
    sortCode: decryptField(row.sortCodeEnc, aad(ownerKey, "sortCodeEnc")),
    accountNumber: decryptField(row.accountNumberEnc, aad(ownerKey, "accountNumberEnc")),
    accountHolderName: decryptField(row.accountHolderNameEnc, aad(ownerKey, "accountHolderNameEnc")),
  };
}

export function userOwnerKey(userId: string): string {
  return `user:${userId}`;
}

/**
 * Stores verified details for a user. The 24h receiving cooling-off (docs/SPEC.md section 7) starts only when the
 * sort code or account number actually change; re-verifying the same account, fixing the holder name or picking
 * a bank does not restart it.
 */
export async function storeUserBankAccount(
  userId: string,
  details: BankDetails,
  now: Date = new Date(),
): Promise<{ account: BankAccount; replaced: boolean; identifiersChanged: boolean }> {
  const ownerKey = userOwnerKey(userId);
  const encrypted = encryptBankDetails(ownerKey, details);
  const existing = await prisma.bankAccount.findUnique({ where: { userId } });
  if (!existing) {
    const account = await prisma.bankAccount.create({
      data: {
        ...encrypted,
        userId,
        providerId: details.providerId,
        copStatus: "MATCH",
        verifiedAt: now,
        createdAt: now,
        changedAt: now,
      },
    });
    return { account, replaced: false, identifiersChanged: false };
  }
  const current = decryptBankDetails(ownerKey, existing);
  const identifiersChanged = current.sortCode !== details.sortCode || current.accountNumber !== details.accountNumber;
  const account = await prisma.bankAccount.update({
    where: { userId },
    data: {
      ...encrypted,
      providerId: details.providerId,
      copStatus: "MATCH",
      verifiedAt: now,
      ...(identifiersChanged ? { changedAt: now } : {}),
    },
  });
  return { account, replaced: true, identifiersChanged };
}

const COOLING_OFF_MS = LIMITS.bankChangeCoolingOffHours * 60 * 60 * 1000;

/** When the account was changed (changedAt after createdAt) and the window is still running. */
export function coolingOffUntil(account: Pick<BankAccount, "createdAt" | "changedAt">, now: number = Date.now()): Date | null {
  if (account.changedAt.getTime() <= account.createdAt.getTime()) return null;
  const end = account.changedAt.getTime() + COOLING_OFF_MS;
  return end > now ? new Date(end) : null;
}
