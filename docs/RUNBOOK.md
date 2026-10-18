# Runbook

How to get from clone to a running app. The TrueLayer sandbox, ngrok and mock-bank sections are filled in during Phase 2; until then they are the checklist from the brief and must be verified against https://docs.truelayer.com before use.

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

## CI

`.github/workflows/ci.yml`: backend job on Ubuntu (`npm ci`, typecheck, test); iOS job on `macos-15` that picks the newest Xcode 16 and the newest plain-numbered iPhone simulator available, then runs `xcodebuild test` for the `QuidApp` scheme (unit + UI tests). The raw xcodebuild log is uploaded as an artifact.

## Secrets

`backend/.env` only. Generate real values with `openssl rand -hex 32` for `PHONE_HASH_PEPPER` and `BANK_DATA_KEY`. Rotating the pepper invalidates every stored phone hash; rotating the key makes stored bank details unreadable, so both need a migration plan before go-live.

## TrueLayer sandbox (Phase 2 — to be verified against the docs)

1. Create a Console account; sandbox is the default. Note the `client_id` (prefixed `sandbox-`) and `client_secret`.
2. Generate an ES512 key pair, upload the public key under Payments settings → Signing keys. Put the private key path in `TRUELAYER_PRIVATE_KEY_PATH` and the key id in `TRUELAYER_KID`.
3. Add the allowed redirect URIs: the universal link and `quid://return/payment`.
4. Run `scripts/ngrok.sh`, set `PUBLIC_BASE_URL` to the https URL, register `<url>/webhooks/truelayer` in the Console.
5. Use the mock provider and TrueLayer's mock bank app on the simulator to exercise app → bank → app.
6. `scripts/sandbox-smoke.ts` (Phase 2) creates a payment and prints the authorisation URL.

## Go-live checklist (Phase 5)

Hosts, keys, `NotImplementedPayeeVerifier` → real CoP, SMS sender, universal-link domain. Filled in during Phase 5.
