// Dev seed: two registered users so the directory and activity feed have something to show.
// Bank accounts are added in Phase 1 once the encryption helper exists. Run with: npm run seed
import { prisma } from "../lib/db.js";
import { hashPhone } from "../lib/phoneHash.js";

const USERS = [
  { phoneE164: "+447700900001", displayName: "Sam Okafor" },
  { phoneE164: "+447700900002", displayName: "Priya Patel" },
  { phoneE164: "+447700900003", displayName: "Tom Whitfield" },
];

async function main(): Promise<void> {
  for (const user of USERS) {
    const phoneHash = hashPhone(user.phoneE164);
    const row = await prisma.user.upsert({
      where: { phoneE164: user.phoneE164 },
      update: { displayName: user.displayName, phoneHash },
      create: { phoneE164: user.phoneE164, phoneHash, displayName: user.displayName },
    });
    console.log(`seeded ${row.displayName} (${row.id})`);
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
