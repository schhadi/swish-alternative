import type { PaymentStatus } from "@prisma/client";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../src/lib/db.js";
import { ALLOWED_FROM, applyTransition, classifyIgnored } from "../src/services/payments/stateMachine.js";
import { toPaymentStatus } from "../src/services/payments/provider.js";
import { createTestApp, resetDatabase, signIn, type TestContext } from "./helpers.js";

const ALL: PaymentStatus[] = ["CREATED", "AUTHORIZING", "AUTHORIZED", "EXECUTED", "SETTLED", "FAILED", "CANCELLED"];

describe("payment state machine", () => {
  let ctx: TestContext;
  let payerId: string;
  let payeeId: string;

  beforeAll(async () => {
    ctx = await createTestApp();
  });

  beforeEach(async () => {
    await resetDatabase();
    ({ userId: payerId } = await signIn(ctx, "07700 900001"));
    ({ userId: payeeId } = await signIn(ctx, "07700 900002"));
  });

  afterAll(async () => {
    await ctx.app.close();
    await prisma.$disconnect();
  });

  async function paymentIn(status: PaymentStatus): Promise<string> {
    const payment = await prisma.payment.create({
      data: { payerUserId: payerId, payeeUserId: payeeId, amountMinor: 1200, reference: "From Sam", status, tlPaymentId: `tl_${status}_${Math.random()}` },
    });
    return payment.id;
  }

  it("applies exactly the allowed transitions and ignores every other pair", async () => {
    for (const from of ALL) {
      for (const to of ALL) {
        const id = await paymentIn(from);
        const outcome = await applyTransition(id, { to, source: "webhook" }, ctx.app.log);
        const row = await prisma.payment.findUniqueOrThrow({ where: { id } });
        if (from === to) {
          expect(outcome).toEqual({ applied: false, reason: "duplicate", current: from });
        } else if (ALLOWED_FROM[to].includes(from)) {
          expect(outcome).toEqual({ applied: true, from, to });
          expect(row.status).toBe(to);
        } else {
          expect(outcome.applied).toBe(false);
          expect(row.status).toBe(from);
          expect(outcome).toMatchObject({ reason: classifyIgnored(from, to), current: from });
        }
      }
    }
  });

  it("keeps a settled payment settled when the executed webhook arrives late", async () => {
    const id = await paymentIn("AUTHORIZING");
    expect((await applyTransition(id, { to: "SETTLED", source: "webhook" }, ctx.app.log)).applied).toBe(true);
    const late = await applyTransition(id, { to: "EXECUTED", source: "webhook" }, ctx.app.log);
    expect(late).toEqual({ applied: false, reason: "stale", current: "SETTLED" });
    const row = await prisma.payment.findUniqueOrThrow({ where: { id } });
    expect(row.status).toBe("SETTLED");
    expect(row.settledAt).not.toBeNull();
  });

  it("classifies ignored transitions so only real conflicts warn", () => {
    expect(classifyIgnored("SETTLED", "EXECUTED")).toBe("stale");
    expect(classifyIgnored("EXECUTED", "AUTHORIZED")).toBe("stale");
    expect(classifyIgnored("FAILED", "SETTLED")).toBe("terminal");
    expect(classifyIgnored("CANCELLED", "EXECUTED")).toBe("terminal");
    expect(classifyIgnored("AUTHORIZED", "CANCELLED")).toBe("invalid");
    expect(classifyIgnored("EXECUTED", "FAILED")).toBe("invalid");
  });

  it("never fails a payment the bank has executed", async () => {
    const id = await paymentIn("EXECUTED");
    const outcome = await applyTransition(id, { to: "FAILED", source: "poll", failureReason: "late" }, ctx.app.log);
    expect(outcome).toEqual({ applied: false, reason: "invalid", current: "EXECUTED" });
    expect((await prisma.payment.findUniqueOrThrow({ where: { id } })).failureReason).toBeNull();
  });

  it("records the failure reason and distinguishes a cancellation", async () => {
    const id = await paymentIn("AUTHORIZING");
    const mapped = toPaymentStatus({ status: "failed", failureReason: "user_canceled" });
    expect(mapped).toEqual({ status: "CANCELLED", failureReason: "user_canceled" });
    await applyTransition(id, { to: mapped.status, source: "poll", failureReason: mapped.failureReason }, ctx.app.log);
    const row = await prisma.payment.findUniqueOrThrow({ where: { id } });
    expect(row.status).toBe("CANCELLED");
    expect(row.failureReason).toBe("user_canceled");
    expect(toPaymentStatus({ status: "failed", failureReason: "insufficient_funds" })).toEqual({ status: "FAILED", failureReason: "insufficient_funds" });
    expect(toPaymentStatus({ status: "failed", failureReason: null })).toEqual({ status: "FAILED", failureReason: "failed" });
  });

  it("survives the same transition arriving twice at once", async () => {
    const id = await paymentIn("AUTHORIZING");
    const outcomes = await Promise.all(Array.from({ length: 5 }, () => applyTransition(id, { to: "EXECUTED", source: "webhook" }, ctx.app.log)));
    expect(outcomes.filter((o) => o.applied)).toHaveLength(1);
    expect(outcomes.filter((o) => !o.applied && o.reason === "duplicate").length + outcomes.filter((o) => !o.applied && o.reason === "contended").length).toBe(4);
  });

  it("reports a missing payment", async () => {
    expect(await applyTransition("nope", { to: "SETTLED", source: "poll" }, ctx.app.log)).toEqual({ applied: false, reason: "missing", current: null });
  });
});
