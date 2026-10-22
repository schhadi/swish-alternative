import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { currentUser, requireAuth } from "../lib/auth.js";
import { prisma } from "../lib/db.js";
import { collectionDetailDTO, collectionDueDTO, organisationDTO } from "../lib/dto.js";
import { HttpError } from "../lib/errors.js";
import { LIMITS } from "../limits.js";
import {
  closeCollection,
  collectionInclude,
  createCollection,
  createOrganisation,
  loadTreasurerCollection,
  organisationInclude,
  remindCollection,
} from "../services/collections/service.js";
import { BankAccountBody } from "./me.js";

const IdParams = z.object({ id: z.string().min(1).max(64) });
const CollectionParams = z.object({ id: z.string().min(1).max(64), cid: z.string().min(1).max(64) });

const OrganisationBody = z.object({
  name: z.string().max(200),
  kind: z.enum(["SOCIETY", "CLUB", "FLAT", "OTHER"]),
  bankAccount: BankAccountBody,
});

const CollectionBody = z.object({
  title: z.string().max(200),
  amountPerPersonMinor: z.number().int(),
  dueAt: z.string().datetime({ offset: true }).nullish(),
  members: z
    .array(z.object({ userId: z.string().min(1).max(64).nullish(), displayName: z.string().max(200).nullish() }))
    .max(LIMITS.collectionMaxMembers * 2)
    .default([]),
});

const RemindBody = z.object({ memberIds: z.array(z.string().min(1).max(64)).max(LIMITS.collectionMaxMembers).optional() }).default({});

/** Collect for the signed-in user (docs/SPEC.md section 5): organisations, collections, reminders, dues. */
export async function organisationRoutes(app: FastifyInstance): Promise<void> {
  const perUser = (request: FastifyRequest) => request.user?.id ?? request.ip;
  // Confirmation of Payee is billed per call and discloses names: the same hourly cap as linking a personal account.
  const verificationLimit = app.rateLimit({ max: LIMITS.bankVerificationsPerHour, timeWindow: "1 hour", keyGenerator: perUser });
  const creationLimit = app.rateLimit({ max: LIMITS.requestCreationsPerMinute, timeWindow: "1 minute", keyGenerator: perUser });
  const reminderLimit = app.rateLimit({ max: LIMITS.reminderCallsPerMinute, timeWindow: "1 minute", keyGenerator: perUser });

  async function detail(collectionId: string) {
    return collectionDetailDTO(await prisma.collection.findUniqueOrThrow({ where: { id: collectionId }, include: collectionInclude }));
  }

  /**
   * Sets up an organisation with the account it collects into. Confirmation of Payee runs first, exactly as for a
   * personal account: only MATCH creates anything; CLOSE_MATCH returns the bank's version of the name to confirm.
   */
  app.post("/orgs", { preHandler: [requireAuth, verificationLimit] }, async (request, reply) => {
    const user = currentUser(request);
    const body = OrganisationBody.parse(request.body);
    const providers = await app.services.providerSource.list();
    if (body.bankAccount.providerId && !providers.some((provider) => provider.id === body.bankAccount.providerId)) {
      throw new HttpError(400, "unknown_provider", "Choose the bank from the list.");
    }
    const { sortCode, accountNumber, accountHolderName } = body.bankAccount;
    const result = await app.services.payeeVerifier.verify(sortCode, accountNumber, accountHolderName);
    request.log.info({ userId: user.id, copStatus: result.status }, "organisation account verification");
    if (result.status === "NO_MATCH") {
      return { copStatus: "NO_MATCH" };
    }
    if (result.status === "CLOSE_MATCH") {
      return { copStatus: "CLOSE_MATCH", suggestedAccountHolderName: result.accountHolderName };
    }
    const orgId = await createOrganisation(
      { creatorUserId: user.id, name: body.name, kind: body.kind, bank: { sortCode, accountNumber, accountHolderName, providerId: body.bankAccount.providerId ?? null } },
      request.log,
    );
    const org = await prisma.organisation.findUniqueOrThrow({ where: { id: orgId }, include: organisationInclude });
    return reply.status(201).send({ copStatus: "MATCH", organisation: organisationDTO(org, "TREASURER", providers) });
  });

  /** Organisations the user looks after, newest collections first. */
  app.get("/orgs", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const providers = await app.services.providerSource.list();
    const memberships = await prisma.orgMember.findMany({
      where: { userId },
      orderBy: { createdAt: "asc" },
      include: { org: { include: organisationInclude } },
    });
    return { organisations: memberships.map((membership) => organisationDTO(membership.org, membership.role, providers)) };
  });

  app.post("/orgs/:id/collections", { preHandler: [requireAuth, creationLimit] }, async (request, reply) => {
    const { id: userId } = currentUser(request);
    const { id: orgId } = IdParams.parse(request.params);
    const body = CollectionBody.parse(request.body);
    const collectionId = await createCollection(
      {
        orgId,
        treasurerUserId: userId,
        title: body.title,
        amountPerPersonMinor: body.amountPerPersonMinor,
        dueAt: body.dueAt ? new Date(body.dueAt) : null,
        members: body.members,
      },
      request.log,
    );
    return reply.status(201).send(await detail(collectionId));
  });

  /** Treasurer only: progress and every member's state. */
  app.get("/orgs/:id/collections/:cid", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const { id: orgId, cid } = CollectionParams.parse(request.params);
    return collectionDetailDTO(await loadTreasurerCollection(cid, userId, orgId));
  });

  app.post("/collections/:id/remind", { preHandler: [requireAuth, reminderLimit] }, async (request) => {
    const { id: userId } = currentUser(request);
    const { id } = IdParams.parse(request.params);
    const { memberIds } = RemindBody.parse(request.body ?? {});
    const outcome = await remindCollection(id, userId, memberIds, request.log);
    return { ...outcome, detail: await detail(id) };
  });

  app.post("/collections/:id/close", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const { id } = IdParams.parse(request.params);
    await closeCollection(id, userId, request.log);
    return detail(id);
  });

  /** Collections the user is on the list of: Home shows the open, unpaid ones with a Pay button. */
  app.get("/collections/due", { preHandler: requireAuth }, async (request) => {
    const { id: userId } = currentUser(request);
    const rows = await prisma.collectionMember.findMany({
      where: { userId },
      orderBy: { createdAt: "desc" },
      take: 50,
      include: { collection: { include: { org: { select: { name: true } } } } },
    });
    return { collections: rows.map(collectionDueDTO) };
  });
}
