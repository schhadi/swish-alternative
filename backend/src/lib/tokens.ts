import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { env } from "../config.js";

/** 256-bit bearer token, URL-safe. Only its SHA-256 is stored (Session.tokenHash). */
export function newSessionToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

/** Six digits, zero-padded, from a CSPRNG. */
export function newOtpCode(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, "0");
}

/** Bound to the phone so a code for one number cannot be replayed for another. */
export function hashOtpCode(phoneE164: string, code: string, pepper: string = env.PHONE_HASH_PEPPER): string {
  return createHmac("sha256", pepper).update(`${phoneE164}:${code}`, "utf8").digest("hex");
}

/** Constant-time comparison of two hex digests. */
export function digestsEqual(a: string, b: string): boolean {
  const bufferA = Buffer.from(a, "hex");
  const bufferB = Buffer.from(b, "hex");
  return bufferA.length === bufferB.length && timingSafeEqual(bufferA, bufferB);
}
