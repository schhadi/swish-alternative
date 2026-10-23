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
  /** A CREATED row that never reached the provider (crash mid-call) is failed after this long, releasing its allowance */
  createdWithoutProviderExpiryMinutes: 10,
  /** Upper bound on one call to the payment provider, so the app's own 20 s timeout sees a real answer */
  providerRequestTimeoutMs: 15_000,
  /**
   * New people one payer can start paying in a rolling 24 hours. Each first payment shows the payee's bank-held name,
   * so this caps how many names one account can learn a day (docs/DECISIONS.md #63, #93).
   */
  newPayeesPer24h: 10,
  /** POST /payments per user per minute */
  paymentCreationsPerMinute: 20,
  /** A webhook whose signed timestamp is further from now than this is logged at warn (never refused) */
  webhookMaxAgeSeconds: 300,
  /** Requests and splits (Phase 3). A split's title is shown in the app; its payment reference is cut to 18 */
  requestTitleMaxLength: 40,
  requestNoteMaxLength: 140,
  /** People one split can ask, and the largest bill a split can describe: £10,000 */
  splitMaxShares: 20,
  splitMaxTotalMinor: 10_000_00,
  /** POST /requests and POST /splits per user per minute */
  requestCreationsPerMinute: 20,
  /** Reminder calls per user per minute, on top of the once-per-24h rule per request */
  reminderCallsPerMinute: 30,
  /** Public pages (invite and split links) per IP per minute */
  publicPagesPerMinutePerIp: 60,
  /** Collect (Phase 4): organisations one user can set up, and the shape of a collection */
  organisationsPerUser: 10,
  organisationNameMaxLength: 60,
  collectionTitleMaxLength: 60,
  collectionMaxMembers: 200,
  /** A due date can be at most this far ahead */
  collectionMaxDueDays: 366,
  /**
   * The collection page is opened by a whole club at once, often behind one campus or mobile network address, so its
   * per-IP caps are generous; the slug space (31^8) is what makes guessing links pointless, not the cap. The return
   * page refreshes itself every few seconds while the bank works, so it has its own, larger bucket.
   */
  collectPagesPerMinutePerIp: 300,
  collectReturnPagesPerMinutePerIp: 600,
  publicPaymentsPerMinutePerIp: 60,
  /** The return page stops refreshing itself after this many tries (about two minutes) */
  collectReturnMaxRefreshes: 40,
} as const;

export type Limits = typeof LIMITS;
