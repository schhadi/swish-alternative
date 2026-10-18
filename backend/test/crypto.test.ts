import { describe, expect, it } from "vitest";
import { decryptField, encryptField } from "../src/lib/crypto.js";
import { digestsEqual, hashOtpCode, hashToken, newOtpCode, newSessionToken } from "../src/lib/tokens.js";

const KEY = "2222222222222222222222222222222222222222222222222222222222222222";

describe("field encryption", () => {
  it("round-trips and never repeats ciphertext", () => {
    const a = encryptField("12-34-56", KEY);
    const b = encryptField("12-34-56", KEY);
    expect(a).not.toBe(b);
    expect(decryptField(a, KEY)).toBe("12-34-56");
    expect(decryptField(b, KEY)).toBe("12-34-56");
  });

  it("fails on tampering or the wrong key", () => {
    const payload = encryptField("12345678", KEY);
    const tampered = Buffer.from(payload, "base64");
    const last = tampered.length - 1;
    tampered[last] = (tampered[last] ?? 0) ^ 0xff;
    expect(() => decryptField(tampered.toString("base64"), KEY)).toThrow();
    expect(() => decryptField(payload, "3".repeat(64))).toThrow();
    expect(() => decryptField("AAAA", KEY)).toThrow();
  });
});

describe("tokens", () => {
  it("session tokens are long, url-safe and hashed consistently", () => {
    const token = newSessionToken();
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(hashToken(token)).toBe(hashToken(token));
    expect(hashToken(token)).not.toBe(hashToken(newSessionToken()));
  });

  it("otp codes are six digits bound to the phone", () => {
    for (let i = 0; i < 50; i += 1) {
      expect(newOtpCode()).toMatch(/^\d{6}$/);
    }
    const a = hashOtpCode("+447700900123", "123456", "pepper");
    expect(a).toBe(hashOtpCode("+447700900123", "123456", "pepper"));
    expect(a).not.toBe(hashOtpCode("+447700900124", "123456", "pepper"));
    expect(a).not.toBe(hashOtpCode("+447700900123", "123457", "pepper"));
    expect(digestsEqual(a, a)).toBe(true);
    expect(digestsEqual(a, hashOtpCode("+447700900123", "000000", "pepper"))).toBe(false);
    expect(digestsEqual("ab", "abcd")).toBe(false);
  });
});
