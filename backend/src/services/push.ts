import type { FastifyBaseLogger } from "fastify";

export type PushKind =
  | "payment_status"
  | "request_received"
  | "request_reminder"
  | "request_paid"
  | "request_declined"
  | "collection_due"
  | "collection_reminder"
  | "collection_paid";

/**
 * Real push notifications are out of scope for v1 (docs/SPEC.md section 10); this log line is the stub. It carries
 * user and object ids only: never names, phone numbers or amounts typed by users.
 */
export function pushStub(log: FastifyBaseLogger, kind: PushKind, recipients: readonly (string | null | undefined)[], context: Record<string, string | number | null>): void {
  log.info({ kind, recipients: recipients.filter((id): id is string => Boolean(id)), ...context }, "push notification (stub)");
}
