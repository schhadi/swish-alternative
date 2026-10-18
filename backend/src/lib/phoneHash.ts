import { createHash, createHmac } from "node:crypto";
import { env } from "../config.js";

/**
 * Two-layer phone hashing (docs/DECISIONS.md, Phase 1):
 *  - clientPhoneHash: SHA-256 of the E.164 number. Computed on the phone for every contact so raw numbers never
 *    leave the device. Unkeyed, because the app has no secret.
 *  - serverPhoneHash: HMAC-SHA256 of the client hash with the server-only pepper. This is what User.phoneHash stores,
 *    so a copy of the database cannot be matched against phone numbers without the pepper.
 */
export function clientPhoneHash(phoneE164: string): string {
  assertE164(phoneE164);
  return createHash("sha256").update(phoneE164, "utf8").digest("hex");
}

export function serverPhoneHash(clientHash: string, pepper: string = env.PHONE_HASH_PEPPER): string {
  if (!/^[0-9a-f]{64}$/.test(clientHash)) {
    throw new Error("serverPhoneHash expects a 64-character lowercase hex client hash");
  }
  return createHmac("sha256", pepper).update(clientHash, "utf8").digest("hex");
}

/** Convenience for the server side: the stored hash for a known E.164 number. */
export function hashPhone(phoneE164: string, pepper: string = env.PHONE_HASH_PEPPER): string {
  return serverPhoneHash(clientPhoneHash(phoneE164), pepper);
}

function assertE164(phoneE164: string): void {
  if (!/^\+[1-9]\d{6,14}$/.test(phoneE164)) {
    throw new Error("expected an E.164 phone number");
  }
}
