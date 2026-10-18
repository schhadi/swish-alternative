import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { currentUser, requireAuth } from "../lib/auth.js";
import { encryptField } from "../lib/crypto.js";
import { prisma } from "../lib/db.js";
import { limitsDTO, publicUser } from "../lib/dto.js";
import { HttpError } from "../lib/errors.js";
import { LIMITS } from "../limits.js";
import { providerDisplayName } from "../services/providers.js";

const DisplayNameBody = z.object({
  displayName: z.string().trim().min(2, "Enter at least 2 characters").max(40, "Keep it under 40 characters"),
});

const digitsOnly = (value: string) => value.replace(/[\s-]/g, "");

const BankAccountBody = z.object({
  sortCode: z.string().transform(digitsOnly).pipe(z.string().regex(/^\d{6}$/, "Sort code is 6 digits")),
  accountNumber: z.string().transform(digitsOnly).pipe(z.string().regex(/^\d{8}$/, "Account number is 8 digits")),
  accountHolderName: z.string().trim().min(2, "Enter the name on the account").max(70, "Keep it under 70 characters"),
  providerId: z.string().min(1).max(64).optional(),
});

const COOLING_OFF_MS = LIMITS.bankChangeCoolingOffHours * 60 * 60 * 1000;

export async function meRoutes(app: FastifyInstance): Promise<void> {
  /** Profile, bank summary (never identifiers) and the limits the server enforces. */
  app.get("/me", { preHandler: requireAuth }, async (request) => {
    const { id } = currentUser(request);
    const user = await prisma.user.findUniqueOrThrow({ where: { id }, include: { bankAccount: true } });
    const providers = await app.services.providerSource.list();
    return {
      user: publicUser(user),
      bankAccount: user.bankAccount ? bankSummary(user.bankAccount, providers) : null,
      limits: limitsDTO(),
    };
  });

  app.put("/me", { preHandler: requireAuth }, async (request) => {
    const { id } = currentUser(request);
    const { displayName } = DisplayNameBody.parse(request.body);
    const user = await prisma.user.update({ where: { id }, data: { displayName } });
    return { user: publicUser(user) };
  });

  /**
   * Links (or replaces) the account the user receives into. Runs Confirmation of Payee first:
   * MATCH stores the details encrypted; CLOSE_MATCH and NO_MATCH store nothing and tell the app what to show.
   */
  app.put("/me/bank-account", { preHandler: requireAuth }, async (request) => {
    const { id } = currentUser(request);
    const body = BankAccountBody.parse(request.body);
    const providers = await app.services.providerSource.list();
    if (body.providerId && !providers.some((provider) => provider.id === body.providerId)) {
      throw new HttpError(400, "unknown_provider", "Choose your bank from the list.");
    }

    const result = await app.services.payeeVerifier.verify(body.sortCode, body.accountNumber, body.accountHolderName);
    if (result.status === "NO_MATCH") {
      return { copStatus: "NO_MATCH" };
    }
    if (result.status === "CLOSE_MATCH") {
      return { copStatus: "CLOSE_MATCH", suggestedAccountHolderName: result.accountHolderName };
    }

    const now = new Date();
    const existing = await prisma.bankAccount.findUnique({ where: { userId: id } });
    const encrypted = {
      sortCodeEnc: encryptField(body.sortCode),
      accountNumberEnc: encryptField(body.accountNumber),
      accountHolderNameEnc: encryptField(body.accountHolderName),
      providerId: body.providerId ?? null,
      copStatus: "MATCH" as const,
      verifiedAt: now,
    };
    const account = existing
      ? await prisma.bankAccount.update({ where: { userId: id }, data: { ...encrypted, changedAt: now } })
      : await prisma.bankAccount.create({ data: { ...encrypted, userId: id, changedAt: now, createdAt: now } });
    request.log.info({ userId: id, replaced: Boolean(existing) }, "bank account linked");
    return { copStatus: "MATCH", bankAccount: bankSummary(account, providers) };
  });

  /** Hard-deletes bank details and the phone hash; keeps the row (anonymised) so payment history stays consistent. */
  app.delete("/me", { preHandler: requireAuth }, async (request, reply) => {
    const { id } = currentUser(request);
    await prisma.$transaction([
      prisma.session.deleteMany({ where: { userId: id } }),
      prisma.bankAccount.deleteMany({ where: { userId: id } }),
      prisma.user.update({
        where: { id },
        data: { phoneE164: null, phoneHash: null, displayName: "Deleted user", deletedAt: new Date() },
      }),
    ]);
    request.log.info({ userId: id }, "account deleted");
    return reply.status(204).send();
  });
}

interface BankAccountRow {
  providerId: string | null;
  copStatus: string;
  verifiedAt: Date | null;
  createdAt: Date;
  changedAt: Date;
}

/** The only view of a bank account the app ever gets. */
export function bankSummary(account: BankAccountRow, providers: Awaited<ReturnType<FastifyInstance["services"]["providerSource"]["list"]>>) {
  const wasChanged = account.changedAt.getTime() - account.createdAt.getTime() > 1_000;
  const coolingOffEnd = account.changedAt.getTime() + COOLING_OFF_MS;
  return {
    bankName: providerDisplayName(account.providerId, providers) ?? "Your bank",
    providerId: account.providerId,
    copStatus: account.copStatus,
    verifiedAt: account.verifiedAt?.toISOString() ?? null,
    coolingOffUntil: wasChanged && coolingOffEnd > Date.now() ? new Date(coolingOffEnd).toISOString() : null,
  };
}
