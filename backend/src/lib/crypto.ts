import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { env } from "../config.js";

const ALGORITHM = "aes-256-gcm";
const IV_BYTES = 12;
const TAG_BYTES = 16;

/**
 * Encrypts one field at rest: base64(iv || ciphertext || tag). Used for sort code, account number and holder name.
 * Decrypt only inside the payment-creation service (Phase 2); never return or log the plaintext.
 */
export function encryptField(plaintext: string, keyHex: string = env.BANK_DATA_KEY): string {
  const key = Buffer.from(keyHex, "hex");
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv(ALGORITHM, key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return Buffer.concat([iv, ciphertext, cipher.getAuthTag()]).toString("base64");
}

export function decryptField(payload: string, keyHex: string = env.BANK_DATA_KEY): string {
  const key = Buffer.from(keyHex, "hex");
  const bytes = Buffer.from(payload, "base64");
  if (bytes.length < IV_BYTES + TAG_BYTES) {
    throw new Error("encrypted payload is too short");
  }
  const iv = bytes.subarray(0, IV_BYTES);
  const tag = bytes.subarray(bytes.length - TAG_BYTES);
  const ciphertext = bytes.subarray(IV_BYTES, bytes.length - TAG_BYTES);
  const decipher = createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString("utf8");
}
