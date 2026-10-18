# Decisions

Choices the brief (`SPEC.md`) doesn't make, with the reasoning. Newest at the bottom. Raise anything here in review; nothing is expensive to undo yet.

## Phase 0

1. **Prisma 6, not 7.** Prisma 7 requires driver adapters and a `prisma.config.ts`; switching database then means swapping an adapter in code. Prisma 6 keeps the "boring" setup the brief describes: `DATABASE_URL` in `.env`, `file:./dev.db` in dev. Moving to Postgres is one line in `prisma/schema.prisma` (`provider = "postgresql"`) plus the URL. No dialect-specific attributes are used.
2. **Prisma enums are used for every status field** (validated on SQLite with `prisma validate` and the init migration). They map to `TEXT` on SQLite and native enums on Postgres with no schema edits.
3. **Schema additions beyond spec section 4**, all nullable or defaulted:
   - `BankAccount.userId` is nullable so organisation accounts can exist without a user (Organisation → BankAccount).
   - `BankAccount.changedAt` drives the 24h receiving cooling-off.
   - `Payment.payerUserId` is nullable and `Payment.payerDisplayName` exists for people who pay a collection from the public web page without an account.
   - `PaymentRequest.lastRemindedAt` backs the once-per-24h reminder rate limit.
   - `User.deletedAt`, `User.phoneE164`/`phoneHash` nullable: account deletion blanks the phone fields and keeps the row so `Payment` history can be anonymised rather than deleted.
   - `OtpChallenge.consumedAt`, `Session.lastUsedAt`: bookkeeping.
4. **Endpoints the UI needs that section 5 doesn't list** (to confirm in Phase 1): `GET /me` returns the profile, a bank *summary* (bank name, CoP status, cooling-off end; never account identifiers) and the current limits; `GET /requests?role=incoming|outgoing`; `GET /orgs` returns organisations with collection summaries. List responses use an envelope (`{ "payments": [...] }`) so metadata can be added later. Payments carry a `counterparty { userId, displayName }` so the feed can render without a second lookup.
5. **Limits live in `backend/src/limits.ts`** and are returned by `GET /me`, so the app shows what the server enforces instead of hard-coding them.
6. **Fastify's logger is configured with options**, not a pino instance: Fastify 5.12's `loggerInstance` type does not accept pino 10's `Logger`. Services receive `app.log` (or a child) as a parameter.
7. **vitest 4.0.18.** vitest 5 requires Node 22 (the brief says Node 20); vitest 4.1 trips an npm 10 peer-resolution bug that breaks a clean `npm ci`.
8. **Xcode project is hand-written** using Xcode 16's file-system-synchronized groups, so adding a Swift file to a folder adds it to the target with no project edits. No XcodeGen. Bundle identifier placeholder: `com.quid.app`.
9. **Two shared schemes:** `QuidApp` (live backend at `localhost:3000`) and `QuidApp-Mock` (`-mock` launch argument). `QUID_API_BASE_URL` overrides the base URL.
10. **MockMode is a `URLProtocol`**, not a second client. The real `APIClient`, JSON decoding and error mapping run in the demo and in tests; only the transport is faked. Fixtures build dates relative to "now" so Today/Yesterday grouping stays realistic.
11. **The app's entry type is `QuidMain`**, not `QuidApp`, so a type never shadows the module name (`QuidApp.Foo`).
12. **Design tokens not in the brief:** failure tint `#FBE8E6` / text `#9A2B1F`; cards are white (`#FFFFFF`) on the `#F6F7F5` background; a secondary fill `#EEF1EF` for secondary buttons and icon tiles. In dark mode surfaces invert and the accent fill stays `#0B6B54`; small accent *text* lightens to `#6CCBAA` to keep 4.5:1 contrast. Letter-spacing is −2 on hero/large amounts and −0.5 on inline amounts (−2 is unreadable at 17pt).
13. **Avatar tints** are six muted background/foreground pairs chosen by a stable FNV hash of the name, so a person keeps their colour across launches and screens.
14. **`NSAllowsLocalNetworking`** is set so the live scheme can reach `http://localhost:3000` on the simulator without disabling App Transport Security generally.
15. **Phase 0 includes a UI shell** for the four tabs on canned data (slightly beyond "scaffold") so the design system could be reviewed as real screens. Later-phase actions open a "Phase N" sheet rather than silently doing nothing.
16. **Repo-root scripts are shell wrappers** that `cd backend`; a TypeScript file in `/scripts` could not resolve `@prisma/client` from `backend/node_modules`.
17. **Legal URLs** are placeholders (`https://quid.example/...`) until real pages exist.

## Phase 0 review fixes

An adversarial review (four lenses, each finding challenged by a skeptic) ran before hand-off; 21 findings were confirmed and fixed. Decisions that came out of it:

18. **System chrome is tinted with `quidAccentText`**, not `quidAccent`: the selected tab, back buttons, toggles, progress bars and the loading spinner need 4.5:1 against dark surfaces, and `#0B6B54` only manages about 2.8:1 there. Filled buttons keep `quidAccent` because their foreground is white (6.5:1). The asset catalog's AccentColor has the same dark-appearance value so UIKit alerts match.
19. **Activity, Collect and Me are card stacks, not `List`s.** `insetGrouped` lists force 10pt corners and SF section headers, which broke the one visual language across tabs. Rows that push a screen draw their own chevron (`QuidChevron`). Navigation titles and segmented controls are set to Manrope once at launch via `UIAppearance` (`QuidAppearance.configure()`), scaled with `UIFontMetrics` so Dynamic Type still applies.
20. **Section headers are 44pt tall** so a trailing text action ("See all") always has a full-size hit target; small headers (day groups, settings groups) are 13pt muted Manrope.
21. **Task cancellation is not an error.** `APIClient` turns `URLError.cancelled` into `CancellationError`, and every ViewModel's `load()` returns quietly on it. Switching tabs mid-load no longer flashes a "cancelled" error card.
22. **Loading placeholders are driven by `isLoading`**, never by "data is nil", so a failed first load shows an error (with retry) instead of permanent shimmer. Account-deletion failures surface in their own alert (`deleteError`) rather than being swallowed.
23. **Pretty logs are an explicit opt-in** (`LOG_PRETTY=1`). `pino-pretty` is a devDependency, so keying it off `NODE_ENV=development` crashed a production start with no fatal log line. `server.ts` now builds the app inside `main()` so any startup failure goes through one handler.
24. **Log redaction uses explicit paths** (`phone`, `*.phone`, `req.body.phone`, …) generated from one `SENSITIVE_FIELDS` list, and `err.code` is deliberately visible. A test logs representative shapes and asserts exactly what is censored. Add a path when you log a new shape; pino's `*` matches one level only.
25. **The test database is recreated on every `npm test`** and test files run sequentially (`fileParallelism: false`), since they share one SQLite file. The Prisma CLI is invoked via `process.execPath`, which also works on Windows.
26. **`Package.resolved` is committed** (the ignore rule was removed) so Phase 2's SPM dependency on the TrueLayer SDK stays reproducible.
27. **Secondary buttons have a visible pressed state** (`quidSurfaceSecondaryPressed`, `#DFE4E1` light / `#323C37` dark); the previous pressed colour was indistinguishable from resting.

