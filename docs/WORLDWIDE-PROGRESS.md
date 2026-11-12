# Worldwide savings progress

The iPhone Worldwide tab shows an optional public comparison chart and ranking. Anyone can read the chart when the hosted service is available; an account and connected banks are required to track a result. No real records are published by development or tests.

## Privacy

Tracking and sharing are separate choices. Starting a plan creates a PRIVATE baseline. Sharing defaults to false, and is enabled only by saving the dedicated public-sharing form. Public profiles use a server-generated Mochi alias, never an Apple name or editable real-name field. Country is manually selected, optional, and can stay hidden even when sharing. No geolocation is inferred.

The public API allowlists alias, optional country, improvement in percentage points, comparison month, update date and rank. It does not return account/user IDs, bank names, balances, exact income/spending, transactions, baseline rate or plan details. Private baseline and account links remain in encrypted account storage.

Switching to private unlists the result and clears the country. Deleting tracking removes its baseline, score and public profile. Disconnecting banks unlists the score. Account deletion unlists before revocation and removes the tracking record with the account. Other users may have saved previously public information; withdrawal cannot erase external copies.

## Comparison method

- Rank improvements in savings RATE, not absolute wealth or currency amounts.
- Savings rate = (income − spending) / income × 100. A move from 10% to 15% is +5 percentage points.
- Starting tracking snapshots a three-complete-month baseline using server-fetched booked bank records. Every baseline month must include income. Manual ledger entries are not accepted as ranking evidence.
- Measurement starts with the next full UTC calendar month after enrollment. For a November 10 start, the first eligible measurement is December, calculated after January 1. No partial-month result is ranked.
- Current measurement is the most recent complete eligible UTC month; charts compare people within the same month. Rankings are descending, equal rounded scores share a rank, with a maximum of 100 entries and the top 10 in the chart.
- Internal transfers are excluded. All compared records must be in one currency. The connected account IDs must match the enrollment snapshot. Changing coverage rejects a new score and unlists the previous one; users can delete tracking and start a new baseline.
- Results are observations after starting a Mochi strategy, not evidence that AI caused savings. Income changes, missing accounts, unusual bills, cash activity and bank history limitations affect the result. These are connected-account cash-flow rates, not verified changes in total net worth.
- This does not establish everyone’s ability to save or rank personal worth. People with no complete income history can keep using private local budgeting without a public score.

## Backend/API

New `community.mjs` computes baseline/measurement and constructs a narrow public response. Account service routes:
- GET `/community/leaderboard?month=YYYY-MM&country=BE` is public and optional country filtering is supported.
- Authenticated GET `/community/me`, POST `/community/start` (currency), POST `/community/refresh`, POST `/community/privacy` (sharing boolean, optional country), DELETE `/community/tracking`.

Client-supplied scores, dates, aliases or user IDs do not set ranking metrics. Baselines use server time and server-side provider imports. Apple reauthentication preserves existing consent/tracking. Public responses have no-store caching headers. Country codes are validated against the public-domain IANA tzdb ISO 3166 list.

## Deployment and limits

The online service still needs the Apple/provider/hosting activation described in APP-ACCOUNTS.md. Until then the UI shows an unavailable-service message and an honest empty chart, not fabricated participants. Banking support currently remains Belgium and Revolut France; showing worldwide country labels does not expand provider coverage.

This filesystem backend is a single-process initial implementation. Public launch requires review of consent copy/privacy disclosures and the activation gates already documented for account registration, plus real multi-account bank-data testing. Scores currently update on explicit user refresh; no background leaderboard computation or notification service is configured.

## Checks

Node tests cover rate comparisons, full-month boundaries, currencies, transfers, incomplete data, changed account coverage, private defaults, generated aliases, optional hidden countries, opt-out removal, deletion, reauthentication persistence and public field allowlisting. iOS is built with Xcode; account/consent operations in tests use synthetic identities and provider records.
