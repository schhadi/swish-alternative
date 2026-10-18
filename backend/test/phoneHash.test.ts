import { describe, expect, it } from "vitest";
import { hashPhone } from "../src/lib/phoneHash.js";

describe("hashPhone", () => {
  it("is stable for the same number and pepper", () => {
    expect(hashPhone("+447700900123", "pepper-a")).toBe(hashPhone("+447700900123", "pepper-a"));
  });

  it("changes with the pepper (salted)", () => {
    expect(hashPhone("+447700900123", "pepper-a")).not.toBe(hashPhone("+447700900123", "pepper-b"));
  });

  it("changes with the number", () => {
    expect(hashPhone("+447700900123", "pepper-a")).not.toBe(hashPhone("+447700900124", "pepper-a"));
  });

  it("produces 64 hex characters", () => {
    expect(hashPhone("+447700900123", "pepper-a")).toMatch(/^[0-9a-f]{64}$/);
  });

  it("rejects numbers that are not E.164", () => {
    expect(() => hashPhone("07700 900123", "pepper-a")).toThrow();
    expect(() => hashPhone("", "pepper-a")).toThrow();
  });
});
