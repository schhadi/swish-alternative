# Runbook

How to get from clone to a running app, and from there to a payment: first against the built-in fake bank, then against the TrueLayer sandbox once the Console values are in `backend/.env`. The sandbox section still has to be verified against https://docs.truelayer.com (see docs/DECISIONS.md #59).

## Prerequisites

- Node 20.12 or later (uses `process.loadEnvFile`), npm 10
- Xcode 16 or later with an iOS 17+ simulator
- (Phase 2) ngrok account, TrueLayer Console account

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
5. Directory: `npm run seed` creates Sam (+44 7700 900001), Priya (…002) and Tom (…003). Add those numbers to a simulator contact and the lookup will mark them registered once the contact picker lands in Phase 2. Until then `POST /directory/lookup` can be exercised with `curl` using SHA-256 hashes of E.164 numbers.
6. `POST /auth/logout` ends the session; `DELETE /me` deletes bank details and blanks the phone number.

MockMode equivalents: code `123456`; sort code `999999` is NO_MATCH; an all-lowercase holder name is CLOSE_MATCH. Launch with `-mock -signed-out` to start on the welcome screen.

## Phase 2: pay someone

### With the fake bank (no TrueLayer account)

1. `backend/.env` has `PAYMENT_PROVIDER=fake` (the default from `.env.example`). Start the backend and run `npm run seed`: Priya (+44 7700 900002) and Tom (…003) get verified fixture accounts.
2. Add Priya's number to a simulator contact, sign in as any other number, link any bank account (MATCH), and tap **Pay**. Allow contacts; Priya appears under "On Quid".
3. Enter an amount and pay. Because the backend answered `provider: "fake"`, the app opens the backend's approval page (`/dev/authorise/<id>`) in a web session instead of the TrueLayer SDK. Approve: the page redirects to `quid://return/payment`, the result screen shows Pending, then Paid once the fake provider reports executed (2 s) and settled (6 s). Decline shows Failed with "Try again".
4. Scriptable: `curl -X POST localhost:3000/dev/payments/<providerPaymentId>/advance -H 'content-type: application/json' -d '{"to":"settled"}'`.
5. Limits are real: £250 per payment, £500 per rolling day, £2,000 per rolling 30 days, counted across payments still in flight.

MockMode (`-mock`): Priya, Tom and Amara can be paid (Amara is a first-time payee and triggers the warning sheet), Jonas has no bank and cannot; any payment turns Paid after about four seconds.

### With the TrueLayer sandbox

Everything here comes from the product brief and TrueLayer's public repositories; confirm each step against https://docs.truelayer.com before relying on it (docs/DECISIONS.md #59).

1. Console (sandbox): note the `client_id` (prefixed `sandbox-`) and `client_secret`.
2. Signing key: `openssl ecparam -genkey -name secp521r1 -noout -out backend/secrets/truelayer-private-key.pem` then `openssl ec -in backend/secrets/truelayer-private-key.pem -pubout -out truelayer-public-key.pem`; upload the public key under Payments settings → Signing keys and copy the key id into `TRUELAYER_KID`.
3. `backend/.env`: `PAYMENT_PROVIDER=truelayer`, `TRUELAYER_ENV=sandbox`, the client id, secret, kid and key path. Hosts default from `TRUELAYER_ENV` (`src/config.ts`, `truelayerHosts()`); override `TRUELAYER_API_BASE_URL` / `TRUELAYER_AUTH_BASE_URL` / `TRUELAYER_HPP_BASE_URL` only if the docs differ. The backend refuses to start if any of the four values is missing.
4. Redirect URI: register `quid://return/payment` (`PAYMENT_RETURN_URI`) in the Console.
5. Webhooks: run `scripts/ngrok.sh`, set `PUBLIC_BASE_URL` to the https URL, `TRUST_PROXY=1`, and register `<url>/webhooks/truelayer` in the Console. Deliveries must carry a `Tl-Signature` whose `jku` is `https://webhooks.truelayer-sandbox.com/.well-known/jwks`; anything else is refused with 403 and logged.
6. Smoke test: `npm run smoke` creates a £1 payment with the mock provider (`SMOKE_PROVIDER_ID`, default `mock-payments-gb-redirect`) to the beneficiary in `SMOKE_SORT_CODE` / `SMOKE_ACCOUNT_NUMBER` / `SMOKE_ACCOUNT_HOLDER_NAME`, prints the authorisation URL and polls the status for two minutes. The first run tells you whether any request shape in `src/services/truelayer/client.ts` needs correcting.
7. App: the `QuidApp` scheme uses the TrueLayer SDK (sandbox). Set `QUID_TRUELAYER_ENV=live` only for a live build; `QUID_HOSTED_PAGE=1` forces the hosted payment page in a web session for debugging. Install TrueLayer's mock bank app on the simulator to approve.
8. The fallback poll runs every minute for payments stuck two minutes without a webhook; `GET /payments/:id` is what the app's result screen reads.

If this is run from the cloud session that built it: `docs.truelayer.com`, `api.truelayer-sandbox.com`, `auth.truelayer-sandbox.com` and `webhooks.truelayer-sandbox.com` must be allowed in the environment's network settings first.

## CI

`.github/workflows/ci.yml`: backend job on Ubuntu (`npm ci`, typecheck, test); iOS job on `macos-15` that picks the newest Xcode 16 and the newest plain-numbered iPhone simulator available, then runs `xcodebuild test` for the `QuidApp` scheme (unit + UI tests). The raw xcodebuild log is uploaded as an artifact. A crashing test host fails the job even when xcodebuild exits 0 (it otherwise relaunches the host and reports the survivors as passed), and on failure the job prints the newest `QuidApp` crash reports and the simulator log lines for the app, so a crash can be read from the job log without the artifact.

## Secrets

`backend/.env` only. Generate real values with `openssl rand -hex 32` for `PHONE_HASH_PEPPER` and `BANK_DATA_KEY`. Rotating the pepper invalidates every stored phone hash; rotating the key makes stored bank details unreadable, so both need a migration plan before go-live.


## Go-live checklist (Phase 5)

Hosts, keys, `NotImplementedPayeeVerifier` → real CoP, SMS sender, universal-link domain. Filled in during Phase 5.
