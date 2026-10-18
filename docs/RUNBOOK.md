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

Environment variables are validated at startup by `src/config.ts`; a missing or malformed value fails fast with the field name.

## iOS

1. Open `ios/QuidApp.xcodeproj`.
2. Pick the **QuidApp-Mock** scheme and run on any iPhone simulator. Everything works with no backend.
3. Pick **QuidApp** to use the backend at `http://localhost:3000`. On a physical device set `QUID_API_BASE_URL` (Edit Scheme → Run → Arguments → Environment) to a reachable URL such as an ngrok tunnel.

MockMode is on when any of these is true: `-mock` launch argument, `QUID_MOCK=1` in the environment, or running in an Xcode preview. Canned responses are in `QuidApp/Networking/MockFixtures.swift`.

Tests: Product → Test, or `scripts/ios-test.sh "iPhone 16"`.

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
