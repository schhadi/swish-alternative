import { randomInt, randomUUID } from "node:crypto";
import { Prisma } from "@prisma/client";
import type { FastifyBaseLogger } from "fastify";
import { env } from "../../config.js";
import type { AuthenticatedUser } from "../../lib/auth.js";
import { prisma } from "../../lib/db.js";
import { HttpError } from "../../lib/errors.js";
import { withKeyedLock } from "../../lib/keyedLock.js";
import { LIMITS } from "../../limits.js";
import { decryptBankDetails, encryptBankDetails, type BankDetails } from "../bankAccounts.js";
import { sendToProvider } from "../payments/create.js";
import type { PaymentProvider } from "../payments/provider.js";
import { assertWithinLimits, pounds } from "../payments/rules.js";
import { pushStub } from "../push.js";
import { referenceFromTitle, visibleLength } from "../requests/rules.js";

/** Collect (docs/SPEC.md sections 1, 5 and 8 screens 7 and 9; docs/DECISIONS.md #81-#88). */

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
/** No look-alike characters, so a slug read off a poster still works. */
const SLUG_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789";
const SLUG_LENGTH = 8;
export const SLUG_PATTERN = new RegExp(`^[${SLUG_ALPHABET}]{${SLUG_LENGTH}}$`);

export function orgOwnerKey(orgId: string): string {
  return `org:${orgId}`;
}

export function collectionLink(slug: string): string {
  return `${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/c/${slug}`;
}

/** Where the bank sends someone who paid from the public page. */
export function collectionReturnUri(): string {
  return `${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/c/return`;
}

function newSlug(): string {
  return Array.from({ length: SLUG_LENGTH }, () => SLUG_ALPHABET[randomInt(SLUG_ALPHABET.length)]).join("");
}

function tidyName(raw: string, maxLength: number, code: string, what: string): string {
  const tidy = raw.trim().replace(/\s+/g, " ");
  if (tidy.length === 0) throw new HttpError(400, code, `Enter ${what}.`);
  if (visibleLength(tidy) > maxLength) throw new HttpError(400, code, `Keep ${what} to ${maxLength} characters.`);
  return tidy;
}

// ---------- Organisations ----------

export const organisationInclude = {
  bankAccount: { select: { providerId: true } },
  collections: {
    orderBy: { createdAt: "desc" },
    include: { members: { select: { status: true } } },
  },
} as const satisfies Prisma.OrganisationInclude;

export type OrganisationRow = Prisma.OrganisationGetPayload<{ include: typeof organisationInclude }>;

/**
 * POST /orgs after Confirmation of Payee said MATCH: the account is stored encrypted under the organisation's own
 * key and the creator becomes its treasurer.
 */
export async function createOrganisation(
  input: { creatorUserId: string; name: string; kind: "SOCIETY" | "CLUB" | "FLAT" | "OTHER"; bank: BankDetails; now?: Date },
  log: FastifyBaseLogger,
): Promise<string> {
  const now = input.now ?? new Date();
  const name = tidyName(input.name, LIMITS.organisationNameMaxLength, "invalid_name", "a name");
  const owned = await prisma.orgMember.count({ where: { userId: input.creatorUserId, role: "TREASURER" } });
  if (owned >= LIMITS.organisationsPerUser) {
    throw new HttpError(400, "organisation_limit", `You can look after up to ${LIMITS.organisationsPerUser} organisations.`);
  }
  const orgId = randomUUID();
  const bankAccountId = randomUUID();
  await prisma.$transaction([
    prisma.bankAccount.create({
      data: {
        id: bankAccountId,
        userId: null,
        ...encryptBankDetails(orgOwnerKey(orgId), input.bank),
        providerId: input.bank.providerId,
        copStatus: "MATCH",
        verifiedAt: now,
        createdAt: now,
        changedAt: now,
      },
    }),
    prisma.organisation.create({ data: { id: orgId, name, kind: input.kind, bankAccountId, createdByUserId: input.creatorUserId, createdAt: now } }),
    prisma.orgMember.create({ data: { orgId, userId: input.creatorUserId, role: "TREASURER", createdAt: now } }),
  ]);
  log.info({ orgId, userId: input.creatorUserId }, "organisation created");
  return orgId;
}

/** The organisation, if this user is its treasurer; 404 otherwise so its existence does not leak. */
export async function loadTreasurerOrganisation(orgId: string, userId: string) {
  const membership = await prisma.orgMember.findUnique({ where: { orgId_userId: { orgId, userId } }, select: { role: true } });
  if (membership?.role !== "TREASURER") {
    throw new HttpError(404, "organisation_not_found", "We couldn't find that organisation.");
  }
  return prisma.organisation.findUniqueOrThrow({ where: { id: orgId } });
}

// ---------- Collections ----------

export const collectionInclude = {
  org: { select: { id: true, name: true } },
  members: { orderBy: [{ createdAt: "asc" }, { id: "asc" }] },
} as const satisfies Prisma.CollectionInclude;

export type CollectionRow = Prisma.CollectionGetPayload<{ include: typeof collectionInclude }>;

export interface NewMember {
  userId?: string | null;
  displayName?: string | null;
}

/** POST /orgs/:id/collections: the collection, its members (people on Quid and plain names) and a short link. */
export async function createCollection(
  input: { orgId: string; treasurerUserId: string; title: string; amountPerPersonMinor: number; dueAt: Date | null; members: readonly NewMember[]; now?: Date },
  log: FastifyBaseLogger,
): Promise<string> {
  const now = input.now ?? new Date();
  await loadTreasurerOrganisation(input.orgId, input.treasurerUserId);
  const title = tidyName(input.title, LIMITS.collectionTitleMaxLength, "invalid_title", "a title");
  if (!Number.isInteger(input.amountPerPersonMinor) || input.amountPerPersonMinor <= 0) {
    throw new HttpError(400, "invalid_amount", "Enter how much each person pays.");
  }
  if (input.amountPerPersonMinor > LIMITS.perPaymentMinor) {
    throw new HttpError(400, "collection_over_limit", `Each person can pay up to ${pounds(LIMITS.perPaymentMinor)}, the most anyone can send in one payment.`, {
      limitMinor: LIMITS.perPaymentMinor,
    });
  }
  if (input.dueAt) {
    if (Number.isNaN(input.dueAt.getTime()) || input.dueAt.getTime() < now.getTime() - DAY_MS) {
      throw new HttpError(400, "invalid_due_date", "Pick a due date from today on.");
    }
    if (input.dueAt.getTime() > now.getTime() + LIMITS.collectionMaxDueDays * DAY_MS) {
      throw new HttpError(400, "invalid_due_date", "Pick a due date within the next year.");
    }
  }
  if (input.members.length > LIMITS.collectionMaxMembers) {
    throw new HttpError(400, "collection_too_many_members", `A collection can have up to ${LIMITS.collectionMaxMembers} people.`);
  }

  // People on Quid are named as Quid knows them; everyone else by the name the treasurer typed.
  const userIds = input.members.map((member) => member.userId).filter((id): id is string => Boolean(id));
  if (new Set(userIds).size !== userIds.length) {
    throw new HttpError(400, "collection_duplicate_member", "Each person can only be in a collection once.");
  }
  const users = await prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, displayName: true, deletedAt: true } });
  const byId = new Map(users.filter((user) => !user.deletedAt && user.displayName !== "").map((user) => [user.id, user.displayName]));
  const members = input.members.map((member) => {
    if (member.userId) {
      const displayName = byId.get(member.userId);
      if (!displayName) throw new HttpError(404, "member_not_found", "We couldn't find one of those people on Quid.");
      return { userId: member.userId, displayName };
    }
    return { userId: null, displayName: tidyName(member.displayName ?? "", 60, "invalid_member_name", "each person's name") };
  });

  const collectionId = randomUUID();
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      await prisma.$transaction([
        prisma.collection.create({
          data: { id: collectionId, orgId: input.orgId, title, amountPerPersonMinor: input.amountPerPersonMinor, dueAt: input.dueAt, slug: newSlug(), createdAt: now },
        }),
        ...members.map((member, index) =>
          prisma.collectionMember.create({
            // A millisecond apart, so the treasurer's order survives sorting by createdAt.
            data: { collectionId, userId: member.userId, displayName: member.displayName, createdAt: new Date(now.getTime() + index) },
          }),
        ),
      ]);
      break;
    } catch (error) {
      // A slug collision: draw again. Anything else is a real failure.
      const slugClash = error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002" && String(error.meta?.target ?? "").includes("slug");
      if (!slugClash || attempt === 4) throw error;
    }
  }
  log.info({ collectionId, orgId: input.orgId, memberCount: members.length }, "collection created");
  for (const member of members) {
    if (member.userId) pushStub(log, "collection_due", [member.userId], { collectionId });
  }
  return collectionId;
}

/** The collection, if this user is treasurer of its organisation; 404 otherwise. */
export async function loadTreasurerCollection(collectionId: string, userId: string, orgId?: string): Promise<CollectionRow> {
  const collection = await prisma.collection.findUnique({ where: { id: collectionId }, include: collectionInclude });
  if (!collection || (orgId && collection.orgId !== orgId)) {
    throw new HttpError(404, "collection_not_found", "We couldn't find that collection.");
  }
  const membership = await prisma.orgMember.findUnique({ where: { orgId_userId: { orgId: collection.orgId, userId } }, select: { role: true } });
  if (membership?.role !== "TREASURER") {
    throw new HttpError(404, "collection_not_found", "We couldn't find that collection.");
  }
  return collection;
}

export function memberNextReminderAt(member: { remindedAt: Date | null }): Date | null {
  return member.remindedAt ? new Date(member.remindedAt.getTime() + LIMITS.reminderMinIntervalHours * HOUR_MS) : null;
}

export interface CollectionReminderResult {
  reminded: string[];
  skipped: { memberId: string; reason: "too_soon" | "paid" | "not_on_quid"; nextReminderAt: string | null }[];
}

/**
 * POST /collections/:cid/remind: every unpaid member on Quid (or the ones named) who was not reminded in the last
 * 24 hours. People added by name only have no way to be reached and are reported as skipped.
 */
export async function remindCollection(collectionId: string, userId: string, memberIds: readonly string[] | undefined, log: FastifyBaseLogger, now: Date = new Date()): Promise<CollectionReminderResult> {
  const collection = await loadTreasurerCollection(collectionId, userId);
  if (collection.status === "CLOSED") {
    throw new HttpError(409, "collection_closed", "This collection is closed.");
  }
  const wanted = memberIds ? new Set(memberIds) : null;
  const windowStart = new Date(now.getTime() - LIMITS.reminderMinIntervalHours * HOUR_MS);
  const outcome: CollectionReminderResult = { reminded: [], skipped: [] };
  for (const member of collection.members) {
    if (wanted && !wanted.has(member.id)) continue;
    if (member.status === "PAID") {
      if (wanted) outcome.skipped.push({ memberId: member.id, reason: "paid", nextReminderAt: null });
      continue;
    }
    if (!member.userId) {
      outcome.skipped.push({ memberId: member.id, reason: "not_on_quid", nextReminderAt: null });
      continue;
    }
    const result = await prisma.collectionMember.updateMany({
      where: { id: member.id, status: "UNPAID", OR: [{ remindedAt: null }, { remindedAt: { lte: windowStart } }] },
      data: { remindedAt: now, remindCount: { increment: 1 } },
    });
    if (result.count === 1) {
      outcome.reminded.push(member.id);
      pushStub(log, "collection_reminder", [member.userId], { collectionId });
    } else {
      const fresh = await prisma.collectionMember.findUnique({ where: { id: member.id }, select: { status: true, remindedAt: true } });
      if (fresh?.status === "PAID") {
        outcome.skipped.push({ memberId: member.id, reason: "paid", nextReminderAt: null });
      } else {
        outcome.skipped.push({ memberId: member.id, reason: "too_soon", nextReminderAt: memberNextReminderAt(fresh ?? member)?.toISOString() ?? null });
      }
    }
  }
  log.info({ collectionId, reminded: outcome.reminded.length, skipped: outcome.skipped.length }, "collection reminders");
  return outcome;
}

/** Stops new payments; ones already at the bank still count when they go through. */
export async function closeCollection(collectionId: string, userId: string, log: FastifyBaseLogger, now: Date = new Date()): Promise<void> {
  await loadTreasurerCollection(collectionId, userId);
  await prisma.collection.updateMany({ where: { id: collectionId, status: "OPEN" }, data: { status: "CLOSED", closedAt: now } });
  log.info({ collectionId }, "collection closed");
}

// ---------- Paying a collection ----------

export type CollectionPayer =
  | { kind: "user"; user: AuthenticatedUser }
  | { kind: "link"; displayName: string; phoneE164: string | null };

export interface CollectionPaymentResult {
  paymentId: string;
  providerPaymentId: string;
  resourceToken: string;
  authorisationUrl: string | null;
  firstTimePayee: boolean;
  organisation: { name: string; providerId: string | null };
  accountHolderName: string;
}

function closedError(): HttpError {
  return new HttpError(410, "collection_closed", "This collection is closed and isn't taking payments.");
}

/**
 * Starts a payment of one share of a collection to the organisation's account: from the app by a member (POST
 * /payments { collectionId }) or from the public page by anyone holding the link. App payers are held to their own
 * limits; link payers are unknown, so only the per-payment limit applies, which the collection's amount already
 * respects. The reference is the collection's title, Faster Payments-safe.
 */
export async function createCollectionPayment(
  provider: PaymentProvider,
  input: { collectionId?: string; slug?: string; payer: CollectionPayer; expectedAmountMinor?: number; now?: Date },
  log: FastifyBaseLogger,
): Promise<CollectionPaymentResult> {
  const now = input.now ?? new Date();
  const where = input.collectionId ? { id: input.collectionId } : { slug: input.slug ?? "" };
  const lockKey = input.payer.kind === "user" ? `payer:${input.payer.user.id}` : `link:${input.collectionId ?? input.slug}`;

  const prepared = await withKeyedLock(lockKey, async () => {
    const collection = await prisma.collection.findUnique({
      where,
      include: { org: { include: { bankAccount: true } } },
    });
    if (!collection) {
      throw new HttpError(404, "collection_not_found", "We couldn't find that collection.");
    }
    if (collection.status === "CLOSED") throw closedError();
    if (input.expectedAmountMinor !== undefined && input.expectedAmountMinor !== collection.amountPerPersonMinor) {
      throw new HttpError(400, "collection_amount_mismatch", `This collection is ${pounds(collection.amountPerPersonMinor)} each.`, {
        amountMinor: collection.amountPerPersonMinor,
      });
    }
    const account = collection.org.bankAccount;
    if (account.copStatus !== "MATCH") {
      throw new HttpError(400, "payee_not_payable", `${collection.org.name} can't receive payments right now.`);
    }

    let memberId: string | null = null;
    let firstTimePayee = false;
    let payerProviderId: string | null = null;
    if (input.payer.kind === "user") {
      const payerId = input.payer.user.id;
      const member = await prisma.collectionMember.findFirst({ where: { collectionId: collection.id, userId: payerId } });
      if (!member) {
        throw new HttpError(403, "not_a_member", "You're not on this collection's list. Ask the treasurer to add you, or pay from the collection's link.");
      }
      if (member.status === "PAID") {
        throw new HttpError(409, "already_paid", "You've already paid this collection.");
      }
      memberId = member.id;
      await assertWithinLimits(prisma, payerId, collection.amountPerPersonMinor, now);
      const earlier = await prisma.payment.count({
        where: { payerUserId: payerId, collection: { orgId: collection.orgId }, status: { in: ["EXECUTED", "SETTLED"] } },
      });
      firstTimePayee = earlier === 0;
      payerProviderId = (await prisma.bankAccount.findUnique({ where: { userId: payerId }, select: { providerId: true } }))?.providerId ?? null;
    }

    const payment = await prisma.payment.create({
      data: {
        payerUserId: input.payer.kind === "user" ? input.payer.user.id : null,
        payerDisplayName: input.payer.kind === "link" ? input.payer.displayName : null,
        payeeUserId: null,
        collectionId: collection.id,
        collectionMemberId: memberId,
        amountMinor: collection.amountPerPersonMinor,
        currency: "GBP",
        reference: referenceFromTitle(collection.title),
        status: "CREATED",
        providerId: payerProviderId,
        createdAt: now,
      },
    });
    return { collection, payment, firstTimePayee, payerProviderId };
  });

  const payer = input.payer;
  const { created, beneficiary } = await sendToProvider(
    provider,
    {
      paymentId: prepared.payment.id,
      amountMinor: prepared.payment.amountMinor,
      reference: prepared.payment.reference,
      beneficiary: () => decryptBankDetails(orgOwnerKey(prepared.collection.orgId), prepared.collection.org.bankAccount),
      payer:
        payer.kind === "user"
          ? { id: payer.user.id, name: payer.user.displayName, phoneE164: payer.user.phoneE164 }
          : { id: `link:${prepared.payment.id}`, name: payer.displayName, phoneE164: payer.phoneE164 },
      providerSelection: prepared.payerProviderId ? { type: "preselected", providerId: prepared.payerProviderId } : { type: "user_selected" },
      returnUri: payer.kind === "user" ? env.PAYMENT_RETURN_URI : collectionReturnUri(),
    },
    log,
  );
  log.info({ paymentId: prepared.payment.id, collectionId: prepared.collection.id, via: payer.kind }, "collection payment started");
  return {
    paymentId: prepared.payment.id,
    providerPaymentId: created.providerPaymentId,
    resourceToken: created.resourceToken,
    authorisationUrl: created.authorisationUrl,
    firstTimePayee: prepared.firstTimePayee,
    organisation: { name: prepared.collection.org.name, providerId: prepared.collection.org.bankAccount.providerId },
    accountHolderName: beneficiary.accountHolderName,
  };
}
