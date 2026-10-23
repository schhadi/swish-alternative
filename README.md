# Quid

A Swish-style, pay-by-phone-number app for the UK, built on open banking. Pick a friend from your contacts, type an amount, approve the payment in your own bank's app. Quid never holds money: every payment is a bank-to-bank Faster Payment initiated through TrueLayer and authorised by the payer inside their bank. Quid is a directory (phone number → bank account) and a UI on top of it.

The full product spec is in [`docs/SPEC.md`](docs/SPEC.md). Work happens phase by phase (spec section 9); each phase ends with tests green, a commit, a summary, and a pause for review.

## Status

| Phase | Scope | State |
| --- | --- | --- |
| 0 | Scaffold: repo layout, backend skeleton + Prisma schema, iOS project + design system + `APIClient` + MockMode, CI, docs | Done, reviewed |
| 1 | Onboarding + directory: OTP sign-in, name, bank account with Confirmation of Payee, providers, contacts hashing + lookup, real (empty) feeds | Done, reviewed |
| 2 | Pay end to end: limits, state machine, signed webhooks, polling, SDK authorisation, result screen; works against the built-in fake bank. Sandbox run pending: TrueLayer hosts were unreachable from the build environment (docs/DECISIONS.md #59) | Done, reviewed |
| 3 | Requests and splits: split flow (equal or custom), split detail with nudges and a shareable link, incoming requests with Pay / Decline, reminders once per 24h, invite links | Done, reviewed |
| 4 | Collect: organisations with a bank-checked account, collections with a link and QR code, treasurer view, reminders, public web pay page, paying a share in the app | Done, reviewed |
| 5 | Hardening: payer and requester cancel, a daily cap on new payees, account deletion asserted end to end, contrast tests in light and dark, accessibility audit UI tests, pay-flow UI tests, universal links (off until a domain exists), the suite on Postgres in CI, runbook with the go-live checklist | **Done, awaiting review** |

Phase 0 also ships a navigable UI shell (Home · Activity · Collect · Me) running on canned data, so the design system can be reviewed on a simulator. Every button now does what it says; the "Phase N" placeholder sheets of the early phases are gone.

## Repository layout

```
/ios        Xcode project (QuidApp) — SwiftUI, iOS 17+, no third-party packages yet
/backend    Fastify + Prisma API (TypeScript, Node 20)
/docs       SPEC.md (the brief), DECISIONS.md (choices not covered by the brief), RUNBOOK.md (how to run things, sandbox setup, go-live checklist)
/scripts    dev helpers: backend dev server, seed, iOS tests, ngrok (Phase 2)
```

## Quick start

### Backend

```bash
cd backend
cp .env.example .env        # dev-only placeholder secrets; never commit .env
npm install                 # also runs prisma generate
npm run db:migrate          # applies migrations to backend/prisma/dev.db (SQLite)
npm run dev                 # http://127.0.0.1:3000/health
npm test                    # vitest, uses prisma/test.db
```

Or just `scripts/dev-backend.sh`, which does all of the above.

### iOS

Open `ios/QuidApp.xcodeproj` in Xcode 16 or later (iOS 17 simulator).

- Scheme **QuidApp-Mock**: runs the app against canned data with no backend. Use this to work on UI.
- Scheme **QuidApp**: talks to the backend at `http://localhost:3000`. Set the `QUID_API_BASE_URL` environment variable in the scheme to point a physical device at an ngrok URL.
- With no session, the welcome screen offers **Explore the demo**, which switches a live build into MockMode. Launch with `-mock -signed-out` to walk onboarding against the mock backend (code `123456`).

Tests: product → Test in Xcode, or `scripts/ios-test.sh`. Unit tests cover money formatting, date grouping, the API client's error mapping (via the same `MockURLProtocol` MockMode uses), every ViewModel and the contrast of every colour pair in light and dark. XCUITests run in MockMode: onboarding, paying (including the first-time warning and a declined payment), requesting, paying a request, creating a collection, and Xcode's accessibility audit over the main screens in light, dark and the largest text size.

### Hosting

The sandbox backend runs on Fly.io in London (one machine, Managed Postgres) from `backend/Dockerfile` and `backend/fly.toml`; `docs/RUNBOOK.md` has the steps, and how to run the demo on an iPhone.

### CI

`.github/workflows/ci.yml` runs `npm test` (plus typecheck and build) on Ubuntu against SQLite, the same suite against Postgres 16, and `xcodebuild test` on a macOS runner with an iPhone simulator.

## Design

The visual language is fixed by spec section 8 (Manrope, `#0B6B54` accent, cards at radius 20, 58pt primary buttons, no gradients, no shadows, no emoji). The layout and interaction patterns follow Apple's Human Interface Guidelines and were checked against current iOS payment apps on Mobbin:

- Home: greeting as the title, two large actions, a horizontal strip of recent people, then activity in one card (cf. [Apple Wallet's card screen](https://mobbin.com/screens/a0767397-5473-4536-944a-d4d3bdc48958), [Revolut home](https://mobbin.com/screens/5be4e584-20cf-45a5-aade-d505997121b7), [Wise recipients](https://mobbin.com/screens/5a670d64-1353-4c11-8299-13d98a178025)).
- Activity: inset-grouped list, grouped by day, searchable, segmented Sent/Received (cf. [Up's payments feed](https://mobbin.com/screens/dcc8ea7e-d329-4544-8b84-3a50afce5acf)).
- Payment detail: hero amount, status pill, receipt rows (cf. [Careem transfer details](https://mobbin.com/screens/7d081fd9-176e-4d5b-86b5-bc75fe6c932e), [Wise transfer timeline](https://mobbin.com/screens/25e11619-e36d-45bd-b170-df6beedef976)).
- Request: tick people, then split equally or per person with a running total and a title (cf. [Vipps even/amount split](https://mobbin.com/screens/29371741-5017-4565-8630-4f2a93ed380b), [Chime add expense](https://mobbin.com/screens/e74ec6a2-da02-4d82-a3df-06bf8a53df16)).
- Split detail: received-of-requested progress, "n of m paid", per-person state, remind button and a copyable link (cf. [Binance split bill](https://mobbin.com/screens/9a761c25-bc5c-46b1-b72f-a6d498857404), [Chime split](https://mobbin.com/screens/deff42f7-bf0f-4b13-854b-17a4aac18b04), [Monzo shared link](https://mobbin.com/screens/a8479f63-774f-4a4e-96b4-64c03c703ec6)).
- Collect link and QR: a large code on a light card, the link with Copy, one Share button (cf. [Careem pay links](https://mobbin.com/screens/b2cde89b-dd5a-4309-86fc-257ae41870ad), [Wise QR](https://mobbin.com/screens/1b27d29a-8939-481b-8bf1-055d366bed92)).
- Collect: progress bar + per-person paid/unpaid rows (cf. [Wise bill split](https://mobbin.com/screens/ba945d27-f5b4-4137-b24a-c9815dac53a5), [Chime split](https://mobbin.com/screens/855cf747-d521-470f-a960-6c4524e9f3d6)).
- Me: avatar header and settings-style grouped rows (cf. [Cash App profile](https://mobbin.com/screens/110068c2-2e43-4f51-a7c5-6cd6bc1e90ba), [CVS account](https://mobbin.com/screens/7bfd68bd-058d-4b39-b097-b448b3ac6ab4)).

Open `ios/QuidApp/DesignSystem/DesignSystemGallery.swift` in the Xcode canvas to see every token and component in light and dark.

## Secrets

Everything secret lives in `backend/.env` (gitignored). `backend/.env.example` is committed with dev placeholders. The iOS app never holds a TrueLayer secret or signing key.
