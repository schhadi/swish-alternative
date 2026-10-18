# Build "Quid" — a pay-by-phone-number iOS app for the UK (open banking)

> Paste this whole file as your first message to Claude Code, or save it as `CLAUDE.md` in an empty repo and say "Read CLAUDE.md and start Phase 0."
> "Quid" is a placeholder name — rename freely.

## 0. How to work

- Work **phase by phase** (Section 9). At the end of each phase: run the tests, commit with a clear message, write a short summary of what works and what's stubbed, then **stop and wait for review** before starting the next phase.
- Before writing any TrueLayer integration code, **fetch and read the current docs at docs.truelayer.com** (Payments API v3, request signing, iOS SDK, webhooks, sandbox and mock bank app). Do not rely on memory for endpoints, field names or SDK package URLs — verify them.
- When a decision isn't covered here, pick the simplest option that keeps the architecture in Section 3 intact, note it in `docs/DECISIONS.md`, and continue. Ask me only if a choice is expensive to undo.
- Never put secrets in the iOS app or in git. Everything secret lives in `backend/.env` (gitignored) with a committed `.env.example`.
- Keep the code boring and readable. No clever abstractions, no third-party dependencies beyond the ones listed unless there's a strong reason.

## 1. What this app is

A Swish-style app for the UK: pay a friend by picking them from your contacts, type an amount, and confirm with Face ID in your own bank's app. Works across every UK bank. The recipient only needs to have registered once; they don't need the app open.

**The app never holds, moves or touches money.** Every payment is a bank-to-bank Faster Payment, initiated through a regulated open-banking provider (TrueLayer) and authorised by the payer inside their bank's app. We are a directory (phone number → bank account) and a UI on top of that.

Three things we do:
1. **Pay** — pick a contact, enter amount, redirect to bank, return, show receipt.
2. **Request / Split** — ask one or several people for money; they pay via the same flow (or via a web link if they don't have the app).
3. **Collect** — a treasurer (society, sports club, flat) sets up a collection ("Trip deposit, £30 each, due 24 Oct"), shares a link/QR, sees who has paid, and nudges who hasn't. This is the paid tier; P2P is free.

Target users for v1: students at one UK university. UK bank accounts only. GBP only.

## 2. Tech stack

**iOS app** (`/ios`)
- Swift 5.10+, SwiftUI, iOS 17+ minimum
- Observation framework (`@Observable`), `async/await`, structured concurrency
- Architecture: feature folders, each with a View + ViewModel (`@Observable` class) + a small set of models. No TCA, no Combine.
- Networking: a single `APIClient` using `URLSession`, typed endpoints, `Codable` DTOs, errors mapped to a small `AppError` enum
- Persistence: Keychain for the session token; `UserDefaults` for trivial flags only; no local DB in v1 (server is the source of truth)
- TrueLayer iOS SDK via Swift Package Manager for payment authorisation (handles bank selection + app-to-app redirect). If the SDK is unsuitable for any reason, fall back to opening the hosted payment page in `ASWebAuthenticationSession`.
- Universal links for the return URI (`https://<domain>/return/payment`), with a custom URL scheme `quid://return/payment` as the dev fallback
- Contacts via `CNContactStore` (permission requested only when the user first taps Pay)
- Tests: XCTest for ViewModels and the payment state mapping; one XCUITest for the pay flow against the mock backend

**Backend** (`/backend`)
- TypeScript, Node 20, Fastify, Zod for validation
- Prisma with SQLite in dev (`file:./dev.db`); schema must also run on Postgres with no changes
- `truelayer-signing` (official npm package) for signing outbound requests and verifying webhook signatures
- `pino` logging, `vitest` for tests
- Runs locally on `:3000`; webhooks reach it via an ngrok tunnel in dev (document the command)

**Repo**
```
/ios            Xcode project (QuidApp)
/backend        Fastify API
/docs           SPEC.md (this file), DECISIONS.md, RUNBOOK.md
/scripts        dev helpers (seed, ngrok, sandbox smoke test)
```

## 3. Architecture (do not change without discussion)

```
iPhone (Quid app)
   │  HTTPS + bearer token
   ▼
Quid backend  ──► TrueLayer Payments API v3 (sandbox)  ──► payer's bank (app-to-app)
   │  ◄── signed webhooks (payment_executed / settled / failed)
   ▼
Postgres/SQLite: users, bank_accounts (encrypted), directory, payments, requests, splits, collections
```

Rules:
- **Payment creation happens on the backend only.** The app never sees the TrueLayer client secret or signing key. The backend creates the payment and returns `{ paymentId, resourceToken, authorisationUrl }` to the app.
- **Webhooks are the source of truth** for payment status. The app's return-from-bank redirect only triggers a status refresh; it never marks anything paid.
- The backend also polls `GET /v3/payments/{id}` as a fallback for payments stuck in `authorizing` for more than 2 minutes (handles users who approve then kill the app).
- Every `POST /v3/payments` carries an `Idempotency-Key` derived from our own payment id, so retries never double-create.

## 4. Data model (Prisma)

```
User           id, phoneE164 (unique), phoneHash (unique, HMAC-SHA256 w/ server pepper), displayName,
               createdAt, lastSeenAt
BankAccount    id, userId (1:1), sortCode, accountNumber, accountHolderName  -- all three encrypted at rest (AES-256-GCM)
               providerId (TrueLayer provider id, nullable; used to preselect the payer's bank), copStatus (MATCH|CLOSE_MATCH|NO_MATCH|UNCHECKED),
               verifiedAt
Payment        id (uuid, ours), payerUserId, payeeUserId (nullable if paying a Collection), collectionId (nullable),
               requestId (nullable), amountMinor, currency='GBP', reference (≤18 chars, Faster Payments safe),
               status: CREATED|AUTHORIZING|AUTHORIZED|EXECUTED|SETTLED|FAILED|CANCELLED,
               tlPaymentId, failureReason, createdAt, updatedAt, settledAt
PaymentRequest id, requesterUserId, payerUserId, amountMinor, reference, note, status: PENDING|PAID|DECLINED|EXPIRED,
               paymentId (nullable), expiresAt (default +14d), createdAt
Split          id, creatorUserId, title, totalMinor, createdAt
SplitShare     id, splitId, userId, amountMinor, requestId
Organisation   id, name, kind: SOCIETY|CLUB|FLAT|OTHER, bankAccountId, createdByUserId
OrgMember      orgId, userId, role: TREASURER|MEMBER
Collection     id, orgId, title, amountPerPersonMinor, dueAt, slug (short, url-safe, unique), status: OPEN|CLOSED
CollectionMember collectionId, userId (nullable for link payers), displayName, status: UNPAID|PAID, paymentId, remindedAt, remindCount
Session        id, userId, tokenHash, expiresAt
OtpChallenge   id, phoneE164, codeHash, expiresAt, attempts
```

Privacy rules baked into the schema and code:
- Phone numbers are matched by `phoneHash` only; the app sends hashes, never raw numbers, when checking which contacts are registered. Pepper lives in `.env`.
- Bank details are decrypted only inside the payment-creation service, never returned to any client, never logged.
- A user can delete their account; this hard-deletes `BankAccount` and `phoneHash` and anonymises their rows in `Payment`.

## 5. Backend API (all JSON, bearer auth unless noted)

Auth
- `POST /auth/otp/start { phone }` — dev mode: code is logged, not sent. Prod: pluggable SMS sender (interface only; stub it).
- `POST /auth/otp/verify { phone, code }` → `{ token, user, isNew }`
- `DELETE /me` — account deletion as above

Onboarding
- `PUT /me { displayName }`
- `PUT /me/bank-account { sortCode, accountNumber, accountHolderName, providerId? }` → runs CoP (Section 6), stores encrypted, returns `{ copStatus }`
- `GET /providers` → proxied list of TrueLayer providers for GB with `id`, `displayName`, `logoUrl` (cache 1h)

Directory
- `POST /directory/lookup { hashes: string[] }` → `{ registered: [{ hash, userId, displayName, firstInitials }] }`. Rate-limit: 1,000 hashes per request, 10 requests/min per user.

Payments
- `POST /payments { payeeUserId | collectionId | requestId, amountMinor, reference }`
  → validates limits (Section 7), creates TrueLayer payment, returns `{ paymentId, tlPaymentId, resourceToken, authorisationUrl, payee: { displayName, copStatus, bankName } }`
- `GET /payments/:id` → status + receipt fields
- `GET /payments?role=sent|received&limit=` → activity feed
- `POST /webhooks/truelayer` — **no bearer auth**; verify `Tl-Signature` with `truelayer-signing`; idempotent on `event_id`; maps `payment_executed → EXECUTED`, `payment_settled → SETTLED`, `payment_failed → FAILED`; emits a push notification stub (log line) to payer and payee

Requests and splits
- `POST /requests { payerUserId, amountMinor, reference, note? }`
- `POST /requests/:id/decline`
- `POST /splits { title, totalMinor, shares: [{ userId, amountMinor }] }` → creates one `PaymentRequest` per share
- `GET /splits/:id`
- `POST /requests/:id/remind` — rate-limited to once per 24h per request

Collect
- `POST /orgs { name, kind, bankAccount: {...} }` → creator becomes TREASURER
- `POST /orgs/:id/collections { title, amountPerPersonMinor, dueAt, members: [{ userId? , displayName }] }` → returns `slug`
- `GET /orgs/:id/collections/:cid` → progress + members (treasurer only)
- `POST /collections/:cid/remind { memberIds? }` → all unpaid if omitted; 24h rate limit per member
- `GET /c/:slug` — **public, no auth**: returns collection title, amount, org name; the web pay page uses this
- `POST /c/:slug/pay { displayName, phone? }` — public: creates a Payment with `collectionId`, returns `authorisationUrl` (hosted payment page), so people without the app can pay from a link or QR

## 6. TrueLayer integration (sandbox first)

Setup (document in `docs/RUNBOOK.md`):
1. Create a Console account; sandbox is the default. Note the `client_id` (prefixed `sandbox-`) and `client_secret`.
2. Generate an ES512 key pair, upload the public key in Console → Payments settings → Signing keys. Private key path goes in `.env`.
3. Add the allowed redirect URIs in Console (universal link + `quid://return/payment`).
4. Register the webhook URL (ngrok URL + `/webhooks/truelayer`).

Backend service `TrueLayerClient`:
- Token: client-credentials grant, scope `payments`, cached until expiry
- `createPayment(input)`: `POST /v3/payments` with `amount_in_minor`, `currency: "GBP"`, `payment_method: { type: "bank_transfer", provider_selection: { type: "preselected", provider_id } | { type: "user_selected" } }`, `beneficiary: { type: "external_account", account_holder_name, account_identifier: { type: "sort_code_account_number", sort_code, account_number }, reference }`, `user: { id, name, phone_number }` — the `name` and `phone_number` are **required for non-regulated clients**; include them. Sign the request body with `truelayer-signing`. Send `Idempotency-Key`.
- `getPayment(id)` for fallback polling
- Webhook verification using the library's `verify` with TrueLayer's JWKS

Authorisation in the app:
- Preferred: TrueLayer iOS SDK → `processSinglePayment(paymentId, resourceToken, redirectURL)`. On completion, call `GET /payments/:id` and show the result screen based on the **server** status.
- Fallback: open `authorisationUrl` (hosted payment page with `#payment_id=…&resource_token=…&return_uri=…`) in `ASWebAuthenticationSession`.
- Sandbox: use the mock provider (currently `mock-payments-gb-redirect` — verify in docs) and TrueLayer's mock bank app on the simulator to exercise the full app → bank → app loop. Add a `scripts/sandbox-smoke.ts` that creates a payment and prints the authorisation URL.

Confirmation of Payee (CoP):
- Define an interface `PayeeVerifier { verify(sortCode, accountNumber, name): Promise<CopResult> }`.
- v1 ships two implementations: `FakePayeeVerifier` (returns MATCH for sandbox test accounts, NO_MATCH for a known-bad fixture, CLOSE_MATCH when the name differs only by case/spacing) and a `NotImplementedPayeeVerifier` that throws, for prod until a Pay.UK aggregator is wired in. Make the UI handle all three results honestly — a NO_MATCH blocks registration; a CLOSE_MATCH shows the bank's version of the name and asks the user to confirm.

## 7. Risk and limits (enforce server-side)

- Default limits: £250 per payment, £500 per rolling 24h per payer, £2,000 per rolling 30 days. Constants in one config file.
- Block a payment if the payee's `copStatus` is `NO_MATCH` or `UNCHECKED`.
- "First time paying this person" flag returned on `POST /payments` so the app shows a warning sheet with the payee's name as held by their bank.
- A user who changes their bank account can't receive payments for 24 hours (cooling-off); show this clearly to them and to anyone trying to pay them.
- Rate limits on OTP (5 attempts), directory lookup, reminders.
- Log every payment state transition with `paymentId`, old → new status, source (`webhook` | `poll` | `user`). Never log account numbers, phone numbers, or tokens.

## 8. Screens and design

Visual language (match this; it's already mocked up):
- Font: **Manrope** (bundle it), weights 600/700/800. Big numbers at 800, letter-spacing −2px on amounts.
- Colours: background `#F6F7F5`, ink `#141A17`, muted text `#5F6B66`, accent green `#0B6B54` (pressed `#084D3D`), success tint `#E3F3EC` / text `#084D3D`, pending amber tint `#FDF1DF` / text `#9A5A12`, hairline `#EDF0EE`. Dark mode: invert surfaces, keep the accent.
- Shapes: cards radius 20–22, primary buttons height 58 radius 18, pills radius 999, avatars are initials on tinted circles. No gradients, no shadows, no emoji in UI.
- Put all of this in `DesignSystem/` as `Color+Quid`, `Font+Quid`, `QuidButton`, `QuidCard`, `Avatar`, `StatusPill`.
- Accessibility: Dynamic Type everywhere, VoiceOver labels on icon buttons, 44pt minimum targets, 4.5:1 contrast.

Screens (one feature folder each):

1. **Onboarding** — phone number → OTP → display name → link bank account (sort code, account number, name; pick your bank from `/providers`) → CoP result → contacts permission explainer. Can be exited and resumed.
2. **Home** — greeting + linked bank line, two big buttons (Pay / Request), recent contacts row (registered contacts first), activity list with status pills, tab bar: Home · Activity · Collect · Me.
3. **Pay** — contact picker (search; registered contacts show a tick + bank name; unregistered show "Invite" which opens a share sheet with an invite link), amount keypad screen with quick-amount pills, reference field (default "From <name>", enforce ≤18 chars), "Pay from" row showing the user's bank, primary button "Pay £X with <Bank>". On tap: `POST /payments` → first-time-payee warning sheet if flagged → SDK authorisation → result.
4. **Payment result** — full-bleed accent screen: Paid / Pending / Failed. Receipt rows (sent at, reference, via, status). "Split this with others" and "Done". Pending shows a spinner and polls every 3s for 60s; after that, "We'll notify you" with the payment left in Activity.
5. **Request** — pick one or several people, amount (equal split or per-person), title → creates a Split. Split detail shows total, progress bar, per-person status, Nudge buttons, copy-link row, "Remind everyone unpaid".
6. **Incoming request** — a request addressed to me shows on Home with Pay / Decline; Pay prefills the Pay flow.
7. **Collect** — org list → collection detail (treasurer view: progress, "X of Y paid", Pay link / Show QR, filter Unpaid/Paid/All, per-member Remind, "Remind all unpaid"). Create-collection form. QR encodes `https://<domain>/c/<slug>`.
8. **Me** — profile, linked bank (change → cooling-off warning), limits, notifications, delete account, legal links, app version.
9. **Web pay page** (backend-served, minimal HTML, no framework) at `/c/:slug` — shows "Pay £30 to Hockey Club — Trip deposit", a name field, a Pay button that creates the payment and redirects to the hosted payment page. This is what the QR code opens for people without the app.

Empty states, error states and loading states for every screen. No lorem ipsum; use realistic placeholder data in previews.

## 9. Phases

**Phase 0 — Scaffold (stop after)**
Repo layout, backend skeleton with health route, Prisma schema + migration, iOS project with DesignSystem and an `APIClient` pointing at `localhost:3000`, a `MockMode` flag that serves canned responses so the UI can be built with no backend. README with run instructions. CI: `npm test` and `xcodebuild test` on a simulator.

**Phase 1 — Onboarding + directory**
OTP (dev: logged), display name, bank account with `FakePayeeVerifier`, provider list, contacts hashing + `/directory/lookup`, Home with real activity feed (empty). Tests: hashing is stable and salted; lookup never returns unregistered hashes.

**Phase 2 — Pay, end to end in sandbox**
`TrueLayerClient`, `POST /payments`, SDK authorisation with mock provider + mock bank app, webhooks via ngrok, polling fallback, result screen, activity updates. Smoke script. Tests: payment state machine (every transition, out-of-order webhooks, duplicates), signing verified against a recorded fixture.

**Phase 3 — Requests and splits**
Requests, splits, incoming requests on Home, reminders with rate limits, invite links for unregistered contacts.

**Phase 4 — Collect**
Orgs, collections, treasurer view, public web pay page, QR, reminders. Tests: public endpoints expose nothing beyond title/amount/org name.

**Phase 5 — Hardening**
Limits and cooling-off, first-time-payee warning, account deletion, dark mode pass, accessibility audit, XCUITest for the pay flow in MockMode, `docs/RUNBOOK.md` covering sandbox setup, ngrok, mock bank app, and the go-live checklist (what changes when swapping sandbox → live: hosts, keys, `NotImplementedPayeeVerifier` → real, SMS sender, universal-link domain).

## 10. Out of scope for v1 (don't build these)

- Holding balances, wallets, cards, Apple Pay, instant-transfer fees
- Android, web app (other than the public pay page)
- Variable Recurring Payments / "pay without the bank bounce"
- Real SMS sending, real CoP, real push notifications — interfaces + stubs only
- Any business/merchant features beyond Collect
- Admin dashboard

## 11. Definition of done for the whole build

- On a simulator, with the backend running and TrueLayer sandbox configured, I can: register with a phone number, link a sandbox bank account, see which of my contacts are registered, pay one of them £12, get bounced to the mock bank app, approve, land back on a "Paid" screen driven by the webhook, and see it in both users' activity.
- I can create a split, the other person sees the request, pays it, and the split shows 1 of 1 paid.
- I can create a collection, open its link in Safari with no app, pay from there, and see the member flip to Paid in the treasurer view.
- `npm test` and `xcodebuild test` pass. No secrets in git. `docs/RUNBOOK.md` gets a new developer from clone to a sandbox payment in under an hour.
