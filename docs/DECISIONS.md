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
