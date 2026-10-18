import { createHmac } from "node:crypto";
import { env } from "../config.js";

/**
 * Directory lookups match on this hash only; the app sends hashes, never raw numbers.
 * HMAC-SHA256 keyed with a server-side pepper, over the E.164 form ("+447700900123").
 */
export function hashPhone(phoneE164: string, pepper: string = env.PHONE_HASH_PEPPER): string {
  if (!/^\+[1-9]\d{6,14}$/.test(phoneE164)) {
    throw new Error("hashPhone expects an E.164 phone number");
  }
  return createHmac("sha256", pepper).update(phoneE164, "utf8").digest("hex");
}
