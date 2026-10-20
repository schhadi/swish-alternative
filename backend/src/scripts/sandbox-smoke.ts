// Creates one sandbox payment with the real TrueLayer client and prints what the app would receive.
// Run with: PAYMENT_PROVIDER=truelayer npm run smoke   (needs the TRUELAYER_* values in backend/.env)
// Beneficiary comes from SMOKE_SORT_CODE / SMOKE_ACCOUNT_NUMBER / SMOKE_ACCOUNT_HOLDER_NAME; use the sandbox test
// account from docs.truelayer.com (not verified from here; see docs/DECISIONS.md #59).
import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { env, truelayerHosts } from "../config.js";
import { TrueLayerClient } from "../services/truelayer/client.js";

async function main(): Promise<void> {
  if (env.PAYMENT_PROVIDER !== "truelayer") {
    throw new Error("Set PAYMENT_PROVIDER=truelayer and the TRUELAYER_* values in backend/.env first");
  }
  const missing = (["TRUELAYER_CLIENT_ID", "TRUELAYER_CLIENT_SECRET", "TRUELAYER_KID", "TRUELAYER_PRIVATE_KEY_PATH"] as const).filter((key) => !env[key]);
  if (missing.length > 0) throw new Error(`Missing ${missing.join(", ")}`);
  const hosts = truelayerHosts();
  const client = new TrueLayerClient({
    ...hosts,
    clientId: env.TRUELAYER_CLIENT_ID as string,
    clientSecret: env.TRUELAYER_CLIENT_SECRET as string,
    kid: env.TRUELAYER_KID as string,
    privateKeyPem: readFileSync(env.TRUELAYER_PRIVATE_KEY_PATH as string, "utf8"),
  });

  const paymentId = randomUUID();
  const created = await client.createPayment({
    paymentId,
    amountMinor: Number(process.env.SMOKE_AMOUNT_MINOR ?? 100),
    currency: "GBP",
    reference: "Quid smoke",
    beneficiary: {
      accountHolderName: process.env.SMOKE_ACCOUNT_HOLDER_NAME ?? "Quid Smoke Test",
      sortCode: process.env.SMOKE_SORT_CODE ?? "123456",
      accountNumber: process.env.SMOKE_ACCOUNT_NUMBER ?? "12345678",
    },
    payer: { id: `smoke-${paymentId}`, name: "Smoke Tester", phoneE164: "+447700900000" },
    providerSelection: { type: "preselected", providerId: process.env.SMOKE_PROVIDER_ID ?? "mock-payments-gb-redirect" },
    returnUri: env.PAYMENT_RETURN_URI,
  });
  console.log(`our payment id:      ${paymentId}`);
  console.log(`provider payment id: ${created.providerPaymentId}`);
  console.log(`status:              ${created.status}`);
  console.log(`authorisation URL:   ${created.authorisationUrl}`);
  console.log("Open the URL, approve in the mock bank, then watch the status below (2 minutes max).");

  const deadline = Date.now() + 120_000;
  let last = created.status;
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 3_000));
    const state = await client.getPayment(created.providerPaymentId);
    if (state.status !== last) {
      console.log(`${new Date().toISOString()} ${state.status}${state.failureReason ? ` (${state.failureReason})` : ""}`);
      last = state.status;
    }
    if (state.status === "settled" || state.status === "failed") break;
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
