import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { z } from "zod";
import { HttpError, buildApp } from "../src/app.js";

describe("error handling", () => {
  const app = buildApp();

  beforeAll(async () => {
    app.post("/_test/validate", async (request) => {
      const body = z.object({ amountMinor: z.number().int().positive() }).parse(request.body);
      return { ok: true, amountMinor: body.amountMinor };
    });
    app.get("/_test/http-error", async () => {
      throw new HttpError(409, "conflict", "Already exists");
    });
    app.get("/_test/boom", async () => {
      throw new Error("secret internal detail");
    });
    await app.ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it("maps Zod validation failures to 400 with issue paths", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/_test/validate",
      payload: { amountMinor: -5 },
    });
    expect(response.statusCode).toBe(400);
    const body = response.json();
    expect(body.error).toBe("validation_error");
    expect(body.issues[0].path).toBe("amountMinor");
  });

  it("passes valid bodies through", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/_test/validate",
      payload: { amountMinor: 1200 },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true, amountMinor: 1200 });
  });

  it("maps HttpError to its status and code", async () => {
    const response = await app.inject({ method: "GET", url: "/_test/http-error" });
    expect(response.statusCode).toBe(409);
    expect(response.json()).toEqual({ error: "conflict", message: "Already exists" });
  });

  it("hides internal error details", async () => {
    const response = await app.inject({ method: "GET", url: "/_test/boom" });
    expect(response.statusCode).toBe(500);
    expect(response.json()).toEqual({ error: "internal_error", message: "Something went wrong" });
  });

  it("rejects malformed JSON bodies with 400", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/_test/validate",
      headers: { "content-type": "application/json" },
      payload: "{not json",
    });
    expect(response.statusCode).toBe(400);
    expect(response.json().error).toBe("bad_request");
  });
});
