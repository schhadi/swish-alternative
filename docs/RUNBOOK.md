# Runbook

How to get from clone to a running app, and from there to a payment: first against the built-in fake bank, then against the TrueLayer sandbox once the Console values are in `backend/.env`. The last section is the go-live checklist: everything that changes between sandbox and live.

The sandbox steps follow the product brief, TrueLayer's public repositories and what could be read of their docs through search results; docs.truelayer.com itself was unreachable from the machine this was written on. Every TrueLayer detail still to confirm is listed in docs/DECISIONS.md #59, and the first sandbox run is where they get confirmed.

## Clone to a sandbox payment (about an hour)

| Step | Time | Section |
| --- | --- | --- |
| 1. Install Node 20.12+, Xcode 16, ngrok; clone the repo | 15 min | Prerequisites |
| 2. Backend up with the fake bank: `scripts/dev-backend.sh`, then `npm run seed` in `backend/` | 5 min | Backend |
| 3. App on the simulator (`QuidApp` scheme), sign in as Sam, pay Priya £12 on the fake bank page | 10 min | Phase 2 › With the fake bank |
| 4. TrueLayer Console: sandbox app, client id and secret, signing key, redirect URI | 15 min | Phase 2 › With the TrueLayer sandbox, steps 1-4 |
| 5. ngrok, `PUBLIC_BASE_URL`, webhook URL in the Console | 5 min | same, step 5 |
| 6. `npm run smoke`: a £1 payment through the mock provider, approved in the browser | 5 min | same, step 6 |
| 7. The same £12 payment from the app with the SDK, approved on the mock bank's page | 5 min | same, step 7 |

If step 6 fails, the error names the call that TrueLayer refused; every request shape lives in `backend/src/services/truelayer/client.ts`.

## Prerequisites

- Node 20.12 or later (uses `process.loadEnvFile`), npm 10
- Xcode 16 or later with an iOS 17+ simulator
- (Phase 2) ngrok account, TrueLayer Console account
- (optional) Postgres 16, to run the backend tests the way CI's Postgres job does

## Backend

```bash
cd backend
cp .env.example .env
npm install            # runs prisma generate
npm run db:migrate     # prisma migrate dev → backend/prisma/dev.db
npm run seed           # three registered dev users
npm run dev            # tsx watch, http://127.0.0.1:3000
curl localhost:3000/health
```

Useful commands:

| Command | What it does |
| --- | --- |
| `npm test` | vitest against `prisma/test.db` (migrations applied automatically) |
| `QUID_TEST_DATABASE_URL=postgresql://… npm test` | the same suite on an empty Postgres database, after switching the schema's `provider` to `postgresql` and running `npx prisma generate` (what CI's Postgres job does; switch it back afterwards) |
| `npm run typecheck` | `tsc --noEmit` over src and tests |
| `npm run db:studio` | Prisma Studio |
| `npm run db:reset` | drop and recreate the dev database |
| `npm run build && npm start` | compiled production run |

Environment variables are validated at startup by `src/config.ts`; a missing or malformed value fails fast with the field name. `LOG_PRETTY=1` (set in `.env.example`) switches on human-readable logs via pino-pretty, a devDependency; leave it unset in production, where logs are JSON. Note that Prisma Client also reads `backend/.env` when it is instantiated (existing variables win), so a stray `.env` next to the schema is picked up even when `NODE_ENV=test` skips our own loader; the test configuration pins every variable it depends on for that reason.

## iOS

1. Open `ios/QuidApp.xcodeproj`.
2. Pick the **QuidApp-Mock** scheme and run on any iPhone simulator. Everything works with no backend.
3. Pick **QuidApp** to use the backend at `http://localhost:3000`. On a physical device set `QUID_API_BASE_URL` (Edit Scheme → Run → Arguments → Environment) to a reachable URL such as an ngrok tunnel. Behind ngrok (or any proxy) set `TRUST_PROXY=1` in `backend/.env`, otherwise every phone shares one per-IP rate-limit bucket.

MockMode is on when any of these is true: `-mock` launch argument, `QUID_MOCK=1` in the environment, or running in an Xcode preview. Canned responses are in `QuidApp/Networking/MockFixtures.swift`.

Tests: Product → Test, or `scripts/ios-test.sh "iPhone 16"`.

## Phase 1: sign up, link a bank, check the directory

1. Backend running (`scripts/dev-backend.sh`), app on the `QuidApp` scheme.
2. Enter any UK mobile number. The code is not sent: read it from the backend log line `SMS not sent (SMS_SENDER=log)`.
3. Pick a name, then link an account. Confirmation of Payee is faked (`COP_VERIFIER=fake`):
   - any sort code / account number with any name: MATCH
   - sort code `99-99-99`: NO_MATCH (blocked)
   - `04-00-04` `87654321` with `priya  patel`: CLOSE_MATCH, bank's name "Priya Patel"
4. Bank details are stored encrypted with `BANK_DATA_KEY`; `GET /me` never returns them.
5. Directory: `npm run seed` creates Sam (+44 7700 900001), Priya (…002) and Tom (…003). Add those numbers to a simulator contact and the Pay and Request pickers list them under "On Quid". `POST /directory/lookup` can also be exercised with `curl` using SHA-256 hashes of E.164 numbers.
6. `POST /auth/logout` ends the session; `DELETE /me` deletes bank details and blanks the phone number.

MockMode equivalents: code `123456`; sort code `999999` is NO_MATCH; an all-lowercase holder name is CLOSE_MATCH. Launch with `-mock -signed-out` to start on the welcome screen.

## Phase 2: pay someone

### With the fake bank (no TrueLayer account)

1. `backend/.env` has `PAYMENT_PROVIDER=fake` (the default from `.env.example`). Start the backend and run `npm run seed`: Priya (+44 7700 900002) and Tom (…003) get verified fixture accounts.
2. Add Priya's number to a simulator contact, sign in as any other number, link any bank account (MATCH), and tap **Pay**. Allow contacts; Priya appears under "On Quid".
3. Enter an amount and pay. Because the backend answered `provider: "fake"`, the app opens the backend's approval page (`/dev/authorise/<id>`) in a web session instead of the TrueLayer SDK. Approve: the page redirects to `quid://return/payment`, the result screen shows Pending, then Paid once the fake provider reports executed (2 s) and settled (6 s). Decline shows Failed with "Try again".
4. Scriptable: `curl -X POST localhost:3000/dev/payments/<providerPaymentId>/advance -H 'content-type: application/json' -d '{"to":"settled"}'`.
5. Limits are real: £250 per payment, £500 per rolling day, £2,000 per rolling 30 days, counted across payments still in flight. Cancel on the first-time sheet, or Cancel in the bank, cancels the payment on the server (`POST /payments/:id/cancel`), which frees its amount at once. A web session closed without pressing either button leaves the payment AUTHORIZING, still counting, because the fake bank never expires it: free it with `curl -X POST localhost:3000/dev/payments/<providerPaymentId>/advance -H 'content-type: application/json' -d '{"to":"failed","failureReason":"canceled"}'` (the id is in the backend log line for the creation) or start over with `npm run db:reset`.
6. A payer can start paying at most 10 new people a day (each first payment shows the payee's name as their bank holds it); the eleventh answers `new_payee_limit`. People paid before don't count.

MockMode (`-mock`): Priya, Tom and Amara can be paid (Amara is a first-time payee and triggers the warning sheet), Jonas has no bank and cannot. A payment turns Paid about two seconds after the mock bank approves it; any amount ending in 13p (£5.13) is declined by the mock bank and shows Failed with Try again.

### With the TrueLayer sandbox

Everything here comes from the product brief and TrueLayer's public repositories; confirm each step against https://docs.truelayer.com before relying on it (docs/DECISIONS.md #59).

1. Console (sandbox): note the `client_id` (prefixed `sandbox-`) and `client_secret`.
2. Signing key: `openssl ecparam -genkey -name secp521r1 -noout -out backend/secrets/truelayer-private-key.pem` then `openssl ec -in backend/secrets/truelayer-private-key.pem -pubout -out truelayer-public-key.pem`; upload the public key under Payments settings → Signing keys and copy the key id into `TRUELAYER_KID`.
3. `backend/.env`: `PAYMENT_PROVIDER=truelayer`, `TRUELAYER_ENV=sandbox`, the client id, secret, kid and key path. Hosts default from `TRUELAYER_ENV` (`src/config.ts`, `truelayerHosts()`); override `TRUELAYER_API_BASE_URL` / `TRUELAYER_AUTH_BASE_URL` / `TRUELAYER_HPP_BASE_URL` only if the docs differ. The backend refuses to start if any of the four values is missing.
4. Redirect URI: register `quid://return/payment` (`PAYMENT_RETURN_URI`) in the Console.
5. Webhooks: run `scripts/ngrok.sh`, set `PUBLIC_BASE_URL` to the https URL, `TRUST_PROXY=1`, and register `<url>/webhooks/truelayer` in the Console. Deliveries must carry a `Tl-Signature` whose `jku` is `https://webhooks.truelayer-sandbox.com/.well-known/jwks`; anything else is refused with 403 and logged.
6. Smoke test: `npm run smoke` creates a £1 payment with the mock provider (`SMOKE_PROVIDER_ID`, default `mock-payments-gb-redirect`, shown as "Mock UK Payments - Redirect Flow") to the beneficiary in `SMOKE_SORT_CODE` / `SMOKE_ACCOUNT_NUMBER` / `SMOKE_ACCOUNT_HOLDER_NAME`, prints the authorisation URL and polls the status for two minutes. Open the URL in a browser: the mock provider's "bank" is a TrueLayer-hosted page (pay-mock-connect.truelayer-sandbox.com) where the outcome is chosen. The first run tells you whether any request shape in `src/services/truelayer/client.ts` needs correcting.
7. App: the `QuidApp` scheme uses the TrueLayer SDK (sandbox). Link "Mock Bank (sandbox)" as your bank before paying, because the real-bank provider ids are unverified (docs/DECISIONS.md #59) and SPEC 6 exercises the mock provider. The SDK opens the mock bank's page; approve there, and the bank returns to `quid://return/payment`, where the result screen waits for the webhook. `QUID_HOSTED_PAGE=1` forces the hosted payment page in a web session for debugging. If TrueLayer's docs name a separate mock bank app for app-to-app redirects, install it on the simulator; the web flow above needs none.
8. The fallback poll runs every minute for payments stuck two minutes without a webhook; `GET /payments/:id` is what the app's result screen reads.
9. Cancelling: Cancel on the first-time sheet, or backing out in the bank, calls `POST /payments/:id/cancel`, which calls TrueLayer's `POST /v3/payments/{id}/actions/cancel`. TrueLayer answers 202 and reports the outcome later, so the payment shows Cancelled once the `payment_failed` webhook (failure reason `canceled`) arrives or the poll sees it; a payment the bank executed anyway stays Paid.

If this is run from the cloud session that built it: `docs.truelayer.com`, `api.truelayer-sandbox.com`, `auth.truelayer-sandbox.com` and `webhooks.truelayer-sandbox.com` must be allowed in the environment's network settings first.

## Phase 3: requests and splits

### With the backend

1. `npm run seed` also gives Sam (+44 7700 900001) two open requests: Priya's "Pizza night" split (£18) and Tom's "Flat Wi-Fi" (£11.25). Sign in as Sam (the code is in the backend log) and link any bank account: Home shows "Requests for you".
2. **Pay** on a request opens the amount screen with the amount and reference fixed. Approve on the fake bank page; once the payment executes the card leaves Home and Activity → Requests shows it as Paid. **Decline** asks first.
3. **Request** on Home: tick people on Quid (their numbers must be in the simulator's contacts), choose "Split equally" (keypad, optional "Include me") or "Custom amounts", add a title and send. The split's detail shows progress, a Nudge per person (once per 24 hours each), the shareable link and "Remind everyone unpaid". To pay a share, sign in as that person on a second simulator.
4. Reminders and new requests are `push notification (stub)` lines in the backend log, with ids only.
5. Invite buttons share `http://localhost:3000/i/<code>`. A split's link is `http://localhost:3000/s/<id>`: open it in the simulator's Safari and tap "Open in Quid" to test the `quid://split/<id>` deep link. Set `APP_DOWNLOAD_URL` to make the pages link to TestFlight or the App Store.
6. Open requests expire after 14 days; the hourly sweep writes EXPIRED, and every read already shows it.

7. The ⋯ menu on a split you created has **Cancel open requests**: everyone who hasn't paid sees it as Cancelled and can't pay it; paid and declined shares stay. A payment already at someone's bank still counts if it goes through.

MockMode (`-mock`): Home shows Priya's and Tom's requests and Activity → Requests also shows Amara's paid one and the "Flat cleaning supplies" split (Priya paid, Amara declined, Tom open and due a nudge). In a split you create, Priya pays her share after five seconds; nobody else pays. Cancelling open requests works on both.

## Phase 4: collect

### With the backend

1. `npm run seed` makes Sam (+44 7700 900001) treasurer of SOAS Hockey Club with an open "Trip deposit" (£30 each: Priya, Tom and Jamie Lee) and puts Sam on Flat 4B's "October bills". The seed prints the Trip deposit's link.
2. In the app, sign in as Sam: Collect lists the club and its collection, and "You're on the list" shows October bills. Home shows it under "Requests for you" with Pay.
3. **New organisation** (the + menu) checks the account with the bank first. Sort code `99-99-99` gives no match, and an all-lowercase name gives a close match that offers the bank's version.
4. **New collection** takes a title, the amount each, an optional due date, and people from contacts (on Quid) or by name. The treasurer view opens with the link, Copy, Show QR and Share.
5. **Pay from the link, no app** (the definition of done): open the link (`http://localhost:3000/c/<slug>`) in Safari on the simulator or the Mac. Enter "Jamie Lee" and a UK mobile number (any valid one; it only goes to the payment service) and tap Pay. The fake bank page opens: approve, and the return page shows Pending, then Paid. Pull to refresh the treasurer view: Jamie Lee is Paid. Another name is added to the list as paid.
6. Remind sends a `push notification (stub)` log line per person on Quid, once a day each. People added by name are listed as needing the link. Close (the ⋯ menu) makes the link answer "closed".
7. Scanning the QR code from a real phone needs a link the phone can reach: run `scripts/ngrok.sh`, set `PUBLIC_BASE_URL` to the https URL and `TRUST_PROXY=1`, then restart the backend.

MockMode (`-mock`): Collect shows SOAS Hockey Club with Trip deposit (7 of 12 paid) and Kit order (3 of 15), and Flat 4B's October bills to pay. In a collection you create, anyone called Priya Patel pays after five seconds.

## Phase 5: hardening

1. Limits and cooling-off: £250 / £500 a day / £2,000 in 30 days, a payee who changed account in the last 24 hours can't be paid (they see it on Me, payers see it in the picker and on the amount screen), and at most 10 new payees a day per payer. All enforced in `backend/src/services/payments/rules.ts` from `backend/src/limits.ts`; `GET /me` returns the numbers the app shows.
2. First-time payee: the sheet shows the name the payee's bank holds. Each time that name is sent, the backend logs `first-time payee name disclosed` with `audit: "payee_name_disclosed"` and ids only.
3. Account deletion (Me → Delete account): bank details and sessions are deleted, the phone number, its hash and the invite code are blanked, the name becomes "Deleted user", open requests to or from them close, and they come off collection lists. Payments stay in the other person's history, to "Deleted user". The number can sign up again as a new person.
4. Dark mode and text size: every colour pair the app draws is checked at 4.5:1 or more in light and dark by `DesignSystemTests`. Launch with `-dark-mode` or `-light-mode` to force an appearance (Edit Scheme → Run → Arguments), and `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` for the largest text.
5. Accessibility audit: `AccessibilityAuditTests` (UI tests) runs Xcode's audit over Home, Activity, a split, Collect, a collection, Me, the pay flow and its result, and the request picker, in light, dark and the largest text size. Each finding prints an `AXAUDIT|…` line; CI collects them under "Accessibility audit findings".
6. Universal links: with `APPLE_APP_IDS` set, `GET /.well-known/apple-app-site-association` claims `/s/*` so a split's shared link opens the app. Turning it on in the app is in the go-live checklist.

## CI

`.github/workflows/ci.yml` has three jobs:

- **Backend · npm test**: Ubuntu, `npm ci`, typecheck, build, test on SQLite.
- **Backend · npm test on Postgres**: a Postgres 16 service, the schema's provider switched to `postgresql`, the schema pushed (`prisma db push`), and the whole suite run against it.
- **iOS · xcodebuild test**: `macos-15` with the newest Xcode 16 and the newest plain-numbered iPhone simulator, `xcodebuild test` for the `QuidApp` scheme (unit and UI tests, including the accessibility audit). The raw log is uploaded as an artifact. A crashing test host fails the job even when xcodebuild exits 0 (it otherwise relaunches the host and reports the survivors as passed); on failure the job prints the newest `QuidApp` crash reports and the app's simulator log lines. UI tests print the screen's accessibility hierarchy when an element never appears, and the job shows it.

## Secrets

`backend/.env` only, never committed (`.env.example` is the committed template). Generate real values with `openssl rand -hex 32` for `PHONE_HASH_PEPPER` and `BANK_DATA_KEY`. Rotating the pepper invalidates every stored phone hash; rotating the key makes stored bank details unreadable, so both need a migration plan before they change in production. The TrueLayer private key lives in `backend/secrets/` (gitignored). Nothing secret is in the app.

## Go-live checklist: sandbox to live

`NODE_ENV=production` makes the backend refuse to start while any dev stand-in is configured (`SMS_SENDER=log`, `COP_VERIFIER=fake`, `PAYMENT_PROVIDER=fake`, the placeholder pepper or the all-zero bank key), so most mistakes below fail at startup rather than in front of a customer.

### TrueLayer

- [ ] Every item in docs/DECISIONS.md #59 confirmed in the sandbox (token endpoint, request and response field names, status vocabulary, hosted payment page URL and its `payment_id` return, Idempotency-Key replay, cancel body, GB provider ids). Fix `backend/src/services/truelayer/client.ts` and `backend/src/services/providers.ts` where they differ.
- [ ] Live Console application approved by TrueLayer, with its own client id and secret (no `sandbox-` prefix): `TRUELAYER_CLIENT_ID`, `TRUELAYER_CLIENT_SECRET`.
- [ ] A new ES512 signing key pair for live (never reuse the sandbox key): public key uploaded in the live Console, `TRUELAYER_KID`, private key at `TRUELAYER_PRIVATE_KEY_PATH`, held in the host's secret store.
- [ ] `TRUELAYER_ENV=live`. The hosts then default to `api.truelayer.com`, `auth.truelayer.com`, `payment.truelayer.com` and the webhook key set at `webhooks.truelayer.com` (`backend/src/config.ts`, `truelayerHosts()`); confirm each against the docs, or set the `TRUELAYER_*_BASE_URL` overrides.
- [ ] Redirect URIs allowed in the live Console: `PAYMENT_RETURN_URI` (`quid://return/payment`, or an https universal link if TrueLayer recommends one for live) and `<PUBLIC_BASE_URL>/c/return` for people paying a collection link in a browser.
- [ ] Webhook URL in the live Console: `<PUBLIC_BASE_URL>/webhooks/truelayer`. Deliveries whose `jku` is not the live JWKS URL are refused with 403.
- [ ] iOS: the SDK environment and API base URL become build settings. Today `AppConfig` reads `QUID_TRUELAYER_ENV` and `QUID_API_BASE_URL` from the scheme's environment, which a TestFlight or App Store build doesn't have, so a release build would use the sandbox and `localhost:3000`. Move both to Info.plist keys set per build configuration.

### Confirmation of Payee and SMS

- [ ] A real `PayeeVerifier` in `backend/src/services/cop.ts` (a CoP provider behind the existing interface), with a new `COP_VERIFIER` value wired in `backend/src/app.ts`. `COP_VERIFIER=none` selects `NotImplementedPayeeVerifier`, which refuses every check, so nobody can link an account until this exists.
- [ ] A real `SmsSender` in `backend/src/services/sms.ts` with a new `SMS_SENDER` value. `SMS_SENDER=none` selects `NotImplementedSmsSender`, which refuses to send, so nobody can sign in until this exists. The sender ID and message template need registering with the SMS provider.
- [ ] Push notifications: `backend/src/services/push.ts` only writes log lines (`push notification (stub)`); real APNs is out of scope for v1 (SPEC 10).

### Domain and links

- [ ] `PUBLIC_BASE_URL` is the live https origin. It is in every QR code, invite, split and collection link, the collection return page and the webhook URL, so choose it once.
- [ ] Universal links for `/s/<id>` split links (needs a paid Apple Developer team):
  - backend: `APPLE_APP_IDS=<Team ID>.<bundle id>`; check `https://<host>/.well-known/apple-app-site-association` answers JSON with no redirect;
  - app: replace `quid.example` in `ios/Config/AssociatedDomains.entitlements` with the host and set the QuidApp target's `CODE_SIGN_ENTITLEMENTS` to `Config/AssociatedDomains.entitlements`. The app already handles `https://<host>/s/<id>` (`DeepLink`).
- [ ] `APP_DOWNLOAD_URL`: the App Store (or TestFlight) link the invite and split pages show.
- [ ] `TRUST_PROXY`: the hop count (or address list) of the load balancer, never `true`, so rate limits see real client addresses.
- [ ] App placeholders: bundle identifier `com.quid.app`, the privacy and terms URLs in `ios/QuidApp/App/AppConfig.swift` (`quid.example`), app icon.

### Keys and data

- [ ] `PHONE_HASH_PEPPER` and `BANK_DATA_KEY`: fresh 32-byte values from `openssl rand -hex 32`, in the host's secret store, backed up. Losing the bank key loses every stored account; changing the pepper breaks every contact match.
- [ ] Postgres: change `provider` in `backend/prisma/schema.prisma` to `postgresql` (CI already runs every test on Postgres 16). The committed migrations are SQLite SQL, so start a Postgres migration history from the schema (`npx prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script` into a new baseline migration) and use `prisma migrate deploy` from then on. Automated backups.
- [ ] Run exactly one backend instance. The per-payer lock that serialises the limits check, the per-collection settlement lock, the rate-limit counters, the fallback poll and the hourly request sweep all live in the process. Before scaling out: move the two locks into Postgres (`pg_advisory_xact_lock` around the check and insert), the rate limiter to a shared store, and the poll and sweep to a single worker.
- [ ] Logs: JSON (`LOG_PRETTY` unset), `LOG_LEVEL=info`, shipped somewhere with retention. They never contain account numbers, phone numbers or tokens; payment transitions and `payee_name_disclosed` audit lines carry ids only.

### Not built in v1

Handing an organisation to another treasurer, deleting an organisation, a requester cancel for single requests in the app (the API has `POST /requests/:id/cancel`; the app cancels a split's open requests), reopening a closed collection, real SMS, CoP and push (SPEC 10).
