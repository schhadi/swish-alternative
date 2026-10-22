// Dev seed: three registered users so the directory, the pay flow and the activity feed have something to show,
// plus two open requests for Sam (Phase 3).
// Run with: npm run seed (idempotent).
import { prisma } from "../lib/db.js";
import { hashPhone } from "../lib/phoneHash.js";
import { storeUserBankAccount } from "../services/bankAccounts.js";
import { createRequest, createSplit } from "../services/requests/service.js";
import type { FastifyBaseLogger } from "fastify";

// Priya and Tom get verified (fixture) accounts so whoever signs in as Sam can pay them straight away.
const USERS = [
  { phoneE164: "+447700900001", displayName: "Sam Okafor", bank: null },
  { phoneE164: "+447700900002", displayName: "Priya Patel", bank: { sortCode: "040004", accountNumber: "87654321", accountHolderName: "Priya Patel", providerId: "ob-starling" } },
  { phoneE164: "+447700900003", displayName: "Tom Whitfield", bank: { sortCode: "200000", accountNumber: "11223344", accountHolderName: "Tom Whitfield", providerId: "ob-barclays" } },
];

/** The services log through Fastify's logger; the seed has none, so their lines are dropped. */
const quiet = { info() {}, warn() {}, error() {}, debug() {}, trace() {}, fatal() {}, child: () => quiet, level: "silent", silent() {} } as unknown as FastifyBaseLogger;

async function main(): Promise<void> {
  const ids: Record<string, string> = {};
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
    ids[user.phoneE164] = row.id;
    console.log(`seeded ${row.displayName} (${row.id})${user.bank ? " with a verified bank account" : ""}`);
  }

  // Phase 3: two open requests for Sam, so Home shows "Requests for you" with Pay and Decline straight away.
  const sam = ids["+447700900001"] as string;
  const priya = ids["+447700900002"] as string;
  const tom = ids["+447700900003"] as string;
  if ((await prisma.paymentRequest.count({ where: { payerUserId: sam } })) === 0) {
    await createSplit({ creatorUserId: priya, title: "Pizza night", totalMinor: 5400, shares: [{ userId: sam, amountMinor: 1800 }, { userId: tom, amountMinor: 1800 }] }, quiet);
    await createRequest({ requesterUserId: tom, payerUserId: sam, amountMinor: 1125, reference: "Flat Wi-Fi", note: "October's share" }, quiet);
    console.log("seeded two open requests for Sam: Priya's Pizza night split and Tom's Wi-Fi request");
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
