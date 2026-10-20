// Dev seed: three registered users so the directory, the pay flow and the activity feed have something to show.
// Run with: npm run seed (idempotent).
import { prisma } from "../lib/db.js";
import { hashPhone } from "../lib/phoneHash.js";
import { storeUserBankAccount } from "../services/bankAccounts.js";

// Priya and Tom get verified (fixture) accounts so whoever signs in as Sam can pay them straight away.
const USERS = [
  { phoneE164: "+447700900001", displayName: "Sam Okafor", bank: null },
  { phoneE164: "+447700900002", displayName: "Priya Patel", bank: { sortCode: "040004", accountNumber: "87654321", accountHolderName: "Priya Patel", providerId: "ob-starling" } },
  { phoneE164: "+447700900003", displayName: "Tom Whitfield", bank: { sortCode: "200000", accountNumber: "11223344", accountHolderName: "Tom Whitfield", providerId: "ob-barclays" } },
];

async function main(): Promise<void> {
  for (const user of USERS) {
    const phoneHash = hashPhone(user.phoneE164);
    const row = await prisma.user.upsert({
      where: { phoneE164: user.phoneE164 },
      update: { displayName: user.displayName, phoneHash },
      create: { phoneE164: user.phoneE164, phoneHash, displayName: user.displayName },
    });
    if (user.bank) {
      const existing = await prisma.bankAccount.findUnique({ where: { userId: row.id } });
      if (!existing) await storeUserBankAccount(row.id, user.bank);
    }
    console.log(`seeded ${row.displayName} (${row.id})${user.bank ? " with a verified bank account" : ""}`);
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
