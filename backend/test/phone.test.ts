import { describe, expect, it } from "vitest";
import { maskPhone, normaliseUKPhone } from "../src/lib/phone.js";

describe("normaliseUKPhone", () => {
  it("accepts the common ways a UK number is written", () => {
    for (const input of ["07700 900123", "07700900123", "+447700900123", "+44 7700 900 123", "0044 7700 900123", "447700900123", "(07700) 900-123", "+44 (0)7700 900123".replace("(0)", "")]) {
      expect(normaliseUKPhone(input)).toBe("+447700900123");
    }
  });

  it("accepts 9-digit national numbers", () => {
    expect(normaliseUKPhone("01632 96001")).toBe("+44163296001");
  });

  it("rejects non-UK and malformed numbers", () => {
    for (const input of ["+15551234567", "+33123456789", "7700900123", "0", "", "abc", "+44", "+4407700900123", "0770090012345"]) {
      expect(normaliseUKPhone(input)).toBeNull();
    }
  });

  it("masks for logs", () => {
    expect(maskPhone("+447700900123")).toBe("+44 7700 ***123");
  });
});
