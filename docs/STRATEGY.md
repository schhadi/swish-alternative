# Quid: pricing strategy and the road to YC

Written against the codebase at commit `e89a3d0` (Phase 5 done). Everything about the product below comes from the repo; market numbers come from the sources listed at the end and are planning figures, not quotes.

## 1. What Quid is, in business terms

Quid is a **directory (phone number to bank account) and a UI on top of open banking**. Every payment is a Faster Payment created through TrueLayer and approved by the payer in their own bank app. Quid never holds money.

That one architectural choice sets the whole commercial shape:

- No float, no interchange, no chargebacks, no safeguarding, no e-money licence. Cost of goods is a per-payment API fee plus a few pence of SMS and name-checking.
- **No fee can be skimmed from a payment.** TrueLayer pays the beneficiary's account directly. Quid is a non-regulated client of a regulated provider. Charging on the flow needs FCA permissions and a payout product, so year-one revenue has to be billed *beside* the flow (subscriptions and licences), not *from* it.

What is built, and what it currently costs the user:

| Product | State in the code | Price today |
| --- | --- | --- |
| Pay (contact, amount, approve in bank) | Done, works end to end against the fake bank; TrueLayer sandbox run still pending (`docs/DECISIONS.md` #59) | Free |
| Request and Split (up to 20 people, nudges, shareable link, invite links) | Done | Free |
| Collect (organisation with a bank-checked account, collections with link and QR, treasurer view, reminders, public web pay page) | Done | Free. `docs/SPEC.md` calls Collect "the paid tier" but nothing in the code bills anyone: no plan, entitlement, subscription or feature gate exists |

Limits that already exist and can become tier boundaries without new concepts: 10 organisations per user, 200 people per collection, 20 people per split, £250 per payment, reminders once per 24 hours per person (`backend/src/limits.ts`).

Not built and on the go-live checklist: real SMS, real Confirmation of Payee, push notifications, Android, a domain, an Apple developer account.

## 2. Five constraints that decide the pricing

1. **Every payment costs Quid money, including free ones.** TrueLayer does not publish prices; third-party guides put pay-by-bank at roughly 0.1 to 0.5 percent or a small fixed fee per payment. Swish and Vipps are free for consumers because the *banks* fund them. Nobody funds Quid's P2P except Quid. The first number a YC partner will ask for is "what does a payment cost you?" Get a written quote before the application.
2. **Payers must never be charged.** Pay by Bank's entire pitch against cards is "free and instant". Collctiv tried a 50p per-payment fee and removed it; it is now free in the UK with an optional tip at withdrawal.
3. **Organisers are the customer.** Treasurers, captains and the flatmate who pays the bills already spend hours chasing people. Spond charges UK clubs 2.5% + 20p per payment; GoCardless 1% + 20p; Collctiv Pro is £9 per admin per month. There is a proven willingness to pay on this side.
4. **At the student wedge, the customer is often the Students' Union, not the society.** Most SUs require society money to sit in the SU's own accounts and ban external accounts (Goldsmiths, Leeds Beckett, Essex, St Andrews all say so in their treasurer guides). Treasurers who collect into a personal account are breaking bye-laws and are personally liable. Collect as built (organisation with its own bank account) fits sports clubs, flats and societies with independent accounts, but to win a whole campus the SU must be able to receive into *its* account with a per-society reference and see everything from one dashboard. That turns the SU into a single buyer and a distribution channel that onboards every treasurer each September.
5. **Apple takes 15 to 30 percent of anything subscribed inside the iOS app, and UK apps still cannot steer users to the web** (the CMA proposed changing this in June 2026; Apple objected; no decision yet). Treasurer tooling is a desktop job anyway. Bill organisations on the web through Stripe and keep the app free of purchase flows.

## 3. Pricing recommendation

Principles: free for people, paid by organisers, priced on what they get (money collected, people chased), billed on the web, with a take-rate on flow as the year-two lever once regulated.

### Tiers

| | Free | Collect Plus | Collect for Unions and Leagues |
| --- | --- | --- | --- |
| Who | Everyone | A flat, a team, a small club, a society with its own account | A Students' Union, a league, a governing body, a multi-team club |
| Price | £0 | **£7 per organisation per month, or £60 per year** (ex VAT). Includes 60 payments received per month, then 10p per payment | **£2,500 / £5,000 / £8,000 per year** for under 5,000 / 5,000 to 15,000 / over 15,000 students (or members), billed annually in September |
| Pay, Request, Split | Yes | Yes | Yes |
| Organisations | 1 | 1 per subscription | Unlimited societies and clubs under the licence |
| Open collections | 2 at a time | Unlimited | Unlimited |
| People per collection | 25 | 200 (the current code cap) | 200 |
| Reminders | Manual, once a day per person | Scheduled auto-chase until paid | Scheduled auto-chase |
| Recurring collections (weekly subs, monthly bills) | No | Yes | Yes |
| Capacity and deadline ("first 20 who pay get a seat") | No | Yes | Yes |
| Treasurers | 1 | Several, with handover | Several, with handover and an SU admin role |
| Export and reconciliation | No | CSV | CSV, per-society reference routing into the SU account, reconciliation export, audit log |
| Verified badge on the pay page | No | Companies House or charity number | SU-verified society |

Why these numbers:

- **£7 a month** is about a third of the value for a typical society (YC's rule of thumb is to charge 25 to 50 percent of value delivered). A treasurer collecting £3,000 a term through Spond pays around £95 in fees; through Quid Plus, £21 for the term. It is still cheaper than Collctiv Pro at £9 per admin, and Quid has no 2 to 3 day withdrawal because the money lands in the organisation's account at once.
- **Annual, in September, to the organisation.** Treasurers rotate every year. A card on file with the organisation survives the handover; a card on a graduating student's phone does not.
- **60 included payments, then 10p.** Flat subscriptions get eaten by a club with 20 members paying weekly subs (80 payments a month). The overage keeps heavy users profitable and is still a tenth of what any card-based platform charges per payment. Set the included number after the TrueLayer quote: if a payment costs 15p, include 40; if 5p, include 100. This is a software usage fee invoiced beside the flow, not a deduction from it; have a regulatory lawyer confirm the wording once.
- **SU licence bands.** SUs run on budgets of millions and already pay five figures a year for membership systems. £5,000 for a 10,000-student union is an easy line item if it removes personal-account collecting and gives the finance office a reconciled feed. Give the first three unions the licence free for a year in exchange for a reference and a case study; the value of "SOAS SU runs every society on Quid" to the YC application is far higher than £2,500.

### The year-two lever: a fee on the flow

Once Quid holds FCA permissions (as an agent of a regulated provider or as a small payment institution; budget six to twelve months and legal cost), add **Collect Business**: 0.75% capped at £1.50 per payment, paid by the organiser, for ticketed events, merchant-style collections and "Pay by Quid" QR codes at a stall or a society bar. Against Spond's 2.5% + 20p, Stripe's 1.5% + 20p and GoCardless's 1% + 20p it is the cheapest way to take money in the UK, and at a planning cost of 5 to 15p per payment the gross margin is 50 to 70 percent. This is the Swish and Vipps MobilePay model (free for people, merchants pay per payment; Vipps MobilePay reported NOK 1.7bn revenue in 2024 on 1.4bn transactions a year). It is the business YC is actually being asked to fund; the subscriptions are the year-one proof that organisers pay.

### Unit economics (planning figures)

| Cost item | Planning figure | Basis |
| --- | --- | --- |
| One pay-by-bank payment via TrueLayer | 5p to 25p | Unpublished; third-party ranges of 0.1 to 0.5 percent or a fixed fee. Get a quote |
| Confirmation of Payee check | 15p to 25p, once per linked account | eSortCode, Credit Canary and TechnoXander list prices |
| OTP text message | 4p to 5p, about one per user per month (sessions last 30 days) | Twilio UK via third-party tables |
| Hosting | about £50 a month at this scale | One Fly.io machine plus managed Postgres |

What that means:

- A free P2P user making six payments a month costs roughly £0.95 a month at 15p a payment, and 20p once for the name check. Ten thousand active free users cost about £9,500 a month. That is the subsidy the paid tiers must cover, and the reason the per-payment price must fall with volume (sixty thousand payments a month is enough to negotiate).
- A society on Plus running eight collections a year of 25 people is 200 payments: £30 of cost against £60 of revenue.
- A weekly-subs club on Plus (80 payments a month) is £12 of cost at 15p against £9 of revenue, and £4 of cost at 5p. Hence the overage and the "set the included count after the quote" rule.

### Illustrative revenue path

| Stage | Customers | Annual revenue |
| --- | --- | --- |
| Year 1, one campus | 1 SU (free as a reference), 40 Plus organisations | about £2,500. The point of year one is the numbers, not the money |
| Year 2, 20 campuses | 20 SU licences, 1,500 Plus organisations, £10m collected with a blended 0.6 percent fee on the business share | about £250,000 |
| Year 3 to 4 | 100 SUs, 10,000 clubs and groups, £150m through Collect | £2m to £3m |

Market context for the application: 2.86 million UK higher-education students across roughly 150 unions with anywhere from 45 to 380 societies each; an estimated 151,000 sports clubs in the UK; and a UK open banking rail already carrying 32 million single payments a month. The UK's own pay-by-mobile-number scheme, Paym, closed in March 2023 and was replaced by single-bank features such as NatWest's Pay Your Contacts. There is no cross-bank alias layer in the UK today. That is the gap Quid fills, and it is the one-line "why now".

## 4. What YC wants to see, and the features that produce it

**Priority zero is not a feature.** YC funds live products with real users and real money, measured weekly. The go-live checklist in `docs/RUNBOOK.md` is the roadmap: TrueLayer live approval, a Confirmation of Payee provider, an SMS sender, a domain, an Apple developer account, App Store or TestFlight. Nothing below matters more than fifty people at one campus paying each other with real money and a weekly growth chart.

Then, in order of leverage:

### A. Growth loop (the K-factor)

1. **Pay a request or a split share from a link, with no app.** Collect already has a public web pay page and the settlement logic for link payers; requests and splits only have a "get the app" page. Extending the web pay page to split shares means every split invites non-users and lets them pay in thirty seconds, then offers them an account to see their history or get paid back. This is the single biggest growth feature available and it reuses code that exists.
2. **Register on the web** (phone, name, bank, name check) so anyone can *receive* without the app. The backend has every endpoint; it needs a few HTML pages like the collect page. This halves the onboarding friction for the receiving side.
3. **Android, or a web app.** StatCounter puts UK mobile at about 51 percent iOS and 49 percent Android. Without Android, half of any friend group cannot be paid and no society can run on Quid alone. The web pay and web registration pages above are the stopgap; Android is the year-one build after launch.
4. **"12 of your contacts are already on Quid."** The directory lookup exists; surface the count on Home and after each payment, with one-tap invites for the rest.

### B. Why organisers pay (the Plus feature set)

5. **Scheduled auto-chase**: a reminder schedule (3 days before due, on the due date, every 3 days after) that runs server-side until paid. Manual reminders with a 24-hour rate limit exist; this makes them automatic.
6. **Recurring collections**: weekly subs, monthly rent and bills, termly membership. Each period creates the collection and chases it. Later, commercial Variable Recurring Payments (live in the UK since June 2026 for lower-risk sectors only, clubs not yet included) make the repeat payment one tap with no bank bounce.
7. **Capacity and deadline**: "£25, 20 places, closes Friday". The first twenty paid get a seat. This is event ticketing without a ticketing fee and a reason a society reaches for Collect instead of a message in the group chat.
8. **Reconciliation**: CSV export, "mark as paid in cash", search, and for unions a per-society payment reference (the 18-character Faster Payments reference is already normalised in code) so the SU finance office can match money to societies automatically.
9. **Treasurer handover and several treasurers**: the runbook lists handover as not built. Treasurers change every year; an organisation that cannot be handed over churns by design.
10. **"What do I owe"**: one view for a member across every collection and request. Home already shows collection dues; make it a screen.

### C. Trust and safety (YC's fintech partners will probe this)

11. **Real Confirmation of Payee and a real SMS sender** behind the existing interfaces, then scam friction beyond the first-time-payee sheet: a warning when the requester is not in the payer's contacts, and a cooling-off on a new device.
12. **Verified organisations**: SU-verified societies, Companies House or charity number for clubs, shown on the pay page and the QR. Verification is what makes a QR on a noticeboard safe to scan.
13. **A payment timeline** on the receipt (created, approved at bank, executed, settled) so "did it go through" never becomes a support ticket.

### D. Measurement and billing

14. **An internal metrics endpoint** from day one: weekly active payers, payments per user per week, share of splits fully paid within 48 hours, collection completion rate and time to complete, invites sent and accepted (K-factor), cost per payment. The YC application and every interview question is about these numbers.
15. **Billing**: a Stripe customer and subscription per organisation, a plan field on `Organisation`, entitlement checks in the backend, feature gates in the app, and a web billing portal. Nothing in the app sells anything.

### E. The bigger story, after YC

16. **Pay by Quid for small merchants**: a QR at a market stall, a society bar or a barber, settled instantly to their account, 0.75 percent capped at £1.50. This is where Swish makes its money.
17. **The regulatory path**: advice on becoming an agent of a regulated provider versus a small payment institution, needed before any fee comes from the flow.

What not to build: wallets or balances, cards, international payments, crypto, buy-now-pay-later, or a general bill-splitting ledger. Each is a different company and each dilutes the "your bank moves the money, we never touch it" story that makes Quid trustworthy and cheap.

## 5. Ninety days to the application

| Weeks | Do | Have at the end |
| --- | --- | --- |
| 1 to 3 | Go-live blockers: TrueLayer live application, CoP provider, SMS sender, domain, Apple account, TestFlight. Get the per-payment quote | Real money moving between two phones |
| 3 to 6 | Launch at one campus with ten societies and clubs. Ship pay-from-link for splits and web registration | First paying users; invites flowing |
| 6 to 10 | Stripe billing for Plus; auto-chase; recurring collections; CSV export | First paid organisations |
| 10 to 13 | Measure; second campus; SU licence conversation with the first union as a reference customer | A weekly growth chart, cohort retention, MRR, cost per payment |

Numbers to have ready: cost per payment, payments per active user per week, percentage of splits paid within 48 hours, number of organisations and how many pay, monthly recurring revenue, four-week retention of payers, and invites per user.

## 6. The questions YC will ask, and the answers

- **"Why won't the banks do this?"** They had it. Paym was a cross-bank pay-by-number scheme run by the banks; they shut it in March 2023 for lack of use and investment, and replaced it with single-bank features. A single bank cannot build a cross-bank directory with organiser workflow; a neutral layer on open banking can.
- **"Collctiv is free."** Collctiv holds the money in a pot, pays out in two to three working days, charges £2.50 to £3 for faster withdrawal and £5 to £10 a month for inactive pots, and asks for a tip. Quid settles instantly into the organisation's own account, holds nothing, and can route into an SU account with a reference. Different product, different cost base.
- **"You depend on TrueLayer."** The code has a `PaymentProvider` interface with two implementations already; Yapily, Token or Plaid slot in behind it. The dependency is on open banking, which is regulated infrastructure, not on one vendor.
- **"The subscription revenue is small."** It is. Its job is to prove that organisers pay and to fund the P2P subsidy. The business is a take-rate on account-to-account flow for groups and small merchants, which is how Swish and Vipps MobilePay make money.
- **"Are you regulated?"** Not today, and not needed while Quid holds no money and takes no fee from the flow. Registration is on the plan before Collect Business launches.

## Sources

- TrueLayer pricing is sales-gated; third-party ranges: [Open Banking Tracker](https://www.openbankingtracker.com/truelayer), [Pay by Bank APIs guide](https://www.openbankingtracker.com/pay-by-bank-apis), [Noda review](https://noda.live/articles/truelayer-review)
- Confirmation of Payee list prices: [eSortCode](https://esortcode.com/confirmation-of-payee), [Credit Canary](https://www.creditcanary.co.uk/connect/confirmation-of-payee), [TechnoXander on G-Cloud](https://www.applytosupply.digitalmarketplace.service.gov.uk/g-cloud/services/716541870915317)
- Twilio UK SMS rates via [textbee](https://textbee.dev/sms-pricing/twilio) and [sent.dm](https://sent.dm/resources/united-kingdom-sms-pricing)
- Collctiv pricing: [Collctiv Pro pricing](https://www.collctiv.com/pricing-collctiv-pro-personal), [Collctiv is now free](https://www.collctiv.com/blog/collctiv-is-now-completely-free), [Collctiv fees FAQ](https://www.collctiv.com/faqs/i-live-in-the-uk-how-much-does-collctiv-cost), [Group Gift Guide fee comparison](https://thegroupgiftguide.com/group-collections/fees)
- Spond fees: [Spond help centre](https://help.spond.com/club/en/articles/58192-what-is-the-transaction-fee-in-spond-club); Pitchero and Teamer figures from [SportMember's comparison](https://www.sportmember.co.uk/en/clubmanagement/best-club-management-software-for-uk-clubs)
- GoCardless pricing summaries: [Dodo Payments](https://dodopayments.com/blogs/gocardless-alternatives/), [Vendr](https://www.vendr.com/marketplace/gocardless)
- Swish model: [Wikipedia](https://en.wikipedia.org/wiki/Swish_(payment)), [Stripe's Swish guide](https://stripe.com/en-cn/resources/more/swish-an-in-depth-guide), [Riksbank Payments Report 2025](https://www.riksbank.se/en-gb/payments--cash/payments-in-sweden/payments-report-2025/safety-efficiency-and-accessibility/are-payments-in-sweden-efficient/more-competition-among-in-store-payment-methods-is-a-good-thing/), [Nordea](https://www.nordea.com/en/news/the-benefits-of-swish-for-businesses-in-sweden)
- Vipps MobilePay: [2025 highlights](https://www.sttinfo.fi/files/69821730/72035243/382370/fi), [rfp.wiki profile](https://www.rfp.wiki/vendors/vipps-mobilepay)
- Paym closure: [Pay.UK](https://www.wearepay.uk/paym-closure/), [The Paypers](https://thepaypers.com/payments/news/uk-banks-decide-to-shut-down-the-paym-payments-system), [NatWest Pay Your Contacts](https://www.ulsterbank.co.uk/support-centre/bank-accounts-and-supporting-information/general/paym.html)
- UK open banking volumes: [Open Banking Expo](https://www.openbankingexpo.com/news/uk-open-banking-ecosystem-surpasses-one-billion-payments-and-100-billion-api-calls/), [Open Banking Limited](https://www.openbanking.org.uk/?p=26475), [Yaspa Index 2026](https://content.yaspa.com/yaspa-index-2026)
- Commercial VRP launch: [Payment Expert, May 2026](https://paymentexpert.com/2026/05/22/uk-cvrps-wave-one-launch-payments/), [Salt Edge, June 2026](https://blog.saltedge.com/salt-edge-enables-commercial-variable-recurring-payments-in-the-uk-under-the-new-ukpi-scheme/), [Payment Expert, October 2026](https://paymentexpert.com/2026/10/05/vrps-future-bank-to-bank-payments/)
- Student numbers and societies: [HESA 2024/25 first release via ACA](https://aca-secretariat.be/newsletter/hesa-publishes-first-release-of-2024-25-uk-student-data/), [Universities UK](https://www.universitiesuk.ac.uk/latest/insights-and-analysis/higher-education-numbers), [Imperial College Union](https://www.imperialcollegeunion.org/node/503), [Winchester SU](https://www.winchesterstudents.co.uk/societies)
- SU rules on society money: [Goldsmiths SU](https://www.goldsmithssu.org/opportunities/toolkit/finance/bank-account/), [Leeds Beckett SU](https://leedsbeckettsu.co.uk/societies/toolbox/), [Essex SU treasurer policies](https://www.essexstudent.com/pageassets/societies/toolkit/FINANCIAL-POLICIES-PROCEDURES-CLUB-SOCIETY-TREASURERS.pdf), [Cambridge Graduate Union finance guide](https://www.gradunion.cam.ac.uk/pageassets/opportunities/support/Society-Finance-Guide.pdf)
- Sports clubs estimate: [Sport and Recreation Alliance 2013 survey](https://sportandrecreation.org.uk/policy/research-publications/sports-club-survey-2013), [CMAE summary](https://www.cmaeurope.org/number-of-sports-clubs-in-uk)
- UK mobile OS share: [StatCounter](https://gs.statcounter.com/os-market-share/mobile/united-kingdom)
- Apple steering rules in the UK: [MacRumors, July 2026](https://www.macrumors.com/2026/07/29/app-store-uk-rules-highly-intrusive/), [CMA proposal coverage](https://mjtsai.com/blog/2026/07/03/uk-cma-proposals-for-external-payments-and-nfc/)
- YC on pricing: [Startup School summary](https://summify.io/discover/most-startups-are-undercharging-dalton-caldwell-RxjZbm/), [YC B2B pricing summary](https://foundevo.beehiiv.com/p/y-combinator-explains-how-to-price-b2b-software-correctly)
