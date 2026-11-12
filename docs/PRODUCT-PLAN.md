# Mochi Money: cash-flow coach and iPhone release

## Product
Help someone answer “What can I put toward my goals each month, and what needs to change?” Keep Mochi’s monochrome, local-first identity. No automatic movement of money.

## Delivery sequence
1. Shared, deterministic planner: three complete calendar months; explicit currency filtering; exclude internal transfers from income/expense while reporting their volume; reject invalid amounts. Count missing months as zero. This is a historical baseline, not a prediction or a verified account balance.
2. Goal waterfall: earliest deadlines first, then undated goals; allocate each available unit once; show monthly need, allocation and shortfall. Default undated goals to 12 months. Offer an adjustable monthly cushion. Category-specific reduction scenarios follow after the MVP.
3. Optional on-device language model: user explicitly requests an explanation. Send only aggregate planner facts, never raw merchant names, notes or account IDs. Computed numbers remain authoritative. Clearly separate generated interpretation from the plan. Unsupported devices retain the planner.
4. Native iOS MVP: local ledger, transaction entry/deletion, CSV import/export, goals, planner; no account required. iPhone bank connections reuse the existing private single-user service and authorized sessions. No implicit desktop/iPhone sync; CSV transfers data explicitly.
5. Beta: compile in Xcode, simulator and physical-device checks, VoiceOver, large text, import failures, offline launch, data deletion, model unavailable/error states, timezone boundaries and goal feasibility.
6. Release: confirm brand rights and bundle ID; enroll appropriate Apple developer entity; configure signing, App Store Connect, icon/screenshots, support/privacy URLs and privacy disclosures; TestFlight; review; release after approval. No promised approval date.

## Follow-on work
Opening balance and verified account snapshots; pending bills/payday calendar; manual recurring commitments and irregular-income scenarios; explicit goal funding ledger; paired transfers and account coverage indicators; import preview/deduplication across statement formats; multi-user secured bank integration for public iOS distribution. Do not label historical surplus “safe to spend”.

## Acceptance
No double-counted transfers or goal allocations. Incomplete and mixed-currency data are visible. Zero/negative surplus never produces a positive contribution. Past-due goals are flagged. Local data remains local. AI failure does not break planning. iOS and macOS share the same planner code.

## Privacy and AI
The initial AI implementation uses Apple's on-device Foundation Models when supported and enabled. No API key or remote AI service. The explanation is experimental and may be wrong; all monetary decisions remain user-controlled. Validate final privacy disclosures against actual release dependencies.

## Release gates still requiring environment/account work
Full Xcode with iOS SDK; signed archive; App Store Connect account/team; device/TestFlight testing; production support and privacy URLs. This repository work is not an App Store submission.

Sources: https://developer.apple.com/app-store/review/guidelines/ (minimum functionality 4.2, privacy 5.1); https://developer.apple.com/documentation/foundationmodels
