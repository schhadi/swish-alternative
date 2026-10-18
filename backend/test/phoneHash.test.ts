import { describe, expect, it } from "vitest";
import { clientPhoneHash, hashPhone, serverPhoneHash } from "../src/lib/phoneHash.js";

describe("phone hashing", () => {
  it("client hash is plain SHA-256 of the E.164 number (shared vector with the iOS tests)", () => {
    expect(clientPhoneHash("+447700900123")).toBe("a8acc3a90a7b4e4dc65e93db9240ed26523050ef754d63b75b5161de76781436");
  });

  it("is stable for the same number and pepper", () => {
    expect(hashPhone("+447700900123", "pepper-a")).toBe(hashPhone("+447700900123", "pepper-a"));
    expect(serverPhoneHash(clientPhoneHash("+447700900123"), "pepper-a")).toBe(hashPhone("+447700900123", "pepper-a"));
  });

  it("changes with the pepper (salted) and with the number", () => {
    expect(hashPhone("+447700900123", "pepper-a")).not.toBe(hashPhone("+447700900123", "pepper-b"));
    expect(hashPhone("+447700900123", "pepper-a")).not.toBe(hashPhone("+447700900124", "pepper-a"));
  });

  it("produces 64 hex characters", () => {
    expect(hashPhone("+447700900123", "pepper-a")).toMatch(/^[0-9a-f]{64}$/);
  });

  it("rejects numbers that are not E.164 and hashes that are not hex", () => {
    expect(() => clientPhoneHash("07700 900123")).toThrow();
    expect(() => clientPhoneHash("")).toThrow();
    expect(() => serverPhoneHash("not-hex", "pepper")).toThrow();
  });
});
