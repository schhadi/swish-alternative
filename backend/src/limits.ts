// Risk limits and rate limits — docs/SPEC.md section 7. Enforced server-side only.
// Amounts are in minor units (pence).

export const LIMITS = {
  /** Maximum single payment: £250 */
  perPaymentMinor: 250_00,
  /** Maximum sent per payer in any rolling 24 hours: £500 */
  rolling24hMinor: 500_00,
  /** Maximum sent per payer in any rolling 30 days: £2,000 */
  rolling30dMinor: 2_000_00,
  /** A payee who changes bank account cannot receive for this long */
  bankChangeCoolingOffHours: 24,
  /** Faster Payments reference length (characters) */
  referenceMaxLength: 18,
  /** OTP attempts before the challenge is locked */
  otpMaxAttempts: 5,
  /** New OTP challenges allowed per phone number in the window below */
  otpStartsPerWindow: 5,
  otpStartWindowMinutes: 15,
  /** Auth routes: requests per IP per minute */
  authRequestsPerMinutePerIp: 30,
  /** Directory lookup: hashes per request and requests per minute per user */
  directoryLookupMaxHashes: 1_000,
  directoryLookupRequestsPerMinute: 10,
  /** Confirmation of Payee calls a per-call-billed external service: cap verifications per user */
  bankVerificationsPerHour: 10,
  /** Reminders (requests and collections): once per 24h per target */
  reminderMinIntervalHours: 24,
  /** Payment requests expire after this many days */
  requestExpiryDays: 14,
  /** Payments stuck in AUTHORIZING longer than this are polled against TrueLayer */
  authorizingPollAfterMinutes: 2,
  /** How often the fallback poll runs, and the least time between two polls of the same payment */
  pollIntervalSeconds: 60,
  /** POST /payments per user per minute */
  paymentCreationsPerMinute: 20,
  /** A webhook whose signed timestamp is older than this is refused (replay protection) */
  webhookMaxAgeSeconds: 300,
} as const;

export type Limits = typeof LIMITS;
