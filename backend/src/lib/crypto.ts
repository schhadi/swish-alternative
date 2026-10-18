import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { env } from "../config.js";

const ALGORITHM = "aes-256-gcm";
const FORMAT_VERSION = 0x01;
const IV_BYTES = 12;
const TAG_BYTES = 16;

/**
 * Encrypts one field at rest: base64(version || iv || ciphertext || tag).
 * `aad` binds the ciphertext to its owner and field (e.g. "user:<id>:sortCode"), so a value copied into another
 * row or column fails to decrypt. The leading version byte lets BANK_DATA_KEY be rotated by re-encrypting in place.
 * Decrypt only inside the bank-account and payment-creation services; never return or log the plaintext.
 */
export function encryptField(plaintext: string, aad: string, keyHex: string = env.BANK_DATA_KEY): string {
  const key = Buffer.from(keyHex, "hex");
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv(ALGORITHM, key, iv);
  cipher.setAAD(Buffer.from(aad, "utf8"));
  const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return Buffer.concat([Buffer.from([FORMAT_VERSION]), iv, ciphertext, cipher.getAuthTag()]).toString("base64");
}

export function decryptField(payload: string, aad: string, keyHex: string = env.BANK_DATA_KEY): string {
  const key = Buffer.from(keyHex, "hex");
  const bytes = Buffer.from(payload, "base64");
  if (bytes.length < 1 + IV_BYTES + TAG_BYTES) {
    throw new Error("encrypted payload is too short");
  }
  if (bytes[0] !== FORMAT_VERSION) {
    throw new Error(`unsupported encrypted payload version ${bytes[0]}`);
  }
  const iv = bytes.subarray(1, 1 + IV_BYTES);
  const tag = bytes.subarray(bytes.length - TAG_BYTES);
  const ciphertext = bytes.subarray(1 + IV_BYTES, bytes.length - TAG_BYTES);
  const decipher = createDecipheriv(ALGORITHM, key, iv);
  decipher.setAAD(Buffer.from(aad, "utf8"));
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString("utf8");
}
