# W Money — banking activation brief

Prepared November 11, 2026. Draft for the owner to review and use in the Enable Banking application. This has not been submitted and no production approval is claimed.

## Product and intended use

W Money is a native iPhone personal budgeting app. People use Sign in with Apple, select a supported bank and approve read-only transaction access at their bank. W Money imports booked transactions, excludes identified transfers between the same person’s accounts from spending, and calculates monthly goal allocations. Optional on-device explanations describe the calculated plan. No payment initiation, money movement, investment trading or bank-password collection is implemented.

The App Store listing is a draft. Public banking access is not active.

Initial bank directory: Belgian personal accounts and Revolut France, subject to provider/bank coverage. Worldwide comparisons do not mean worldwide bank coverage. Expansion requires coverage checks and updates to the explicit directory restrictions.

## Requested provider activation

Request production access approved for public/commercial users, rather than only the owner’s whitelisted test accounts. Confirm supported banks, countries, transaction history, consent duration, commercial terms, pricing, permitted use of transaction-derived statistics and the requirements applying to the publisher. No provider contract or payment has been accepted.

## Data handling implemented

- Transactions are read with `balances:false`; only booked records are imported.
- Bank authentication and consent occur through the provider/bank authorization flow.
- Apple identity tokens are verified server-side and exchanged for an app session. Device credentials use iOS Keychain.
- Account and bank-session files use authenticated encryption. One service process owns persistent storage. Secrets are absent from the app bundle.
- Disconnect and account deletion revoke bank sessions. Signed Apple revocation notifications invalidate app access before cleanup and support retry.
- Savings progress tracking is private by default. Separate opt-in sharing publishes only a generated alias, optional self-selected country, comparison period and savings-rate improvement. Amounts, transactions and account IDs are not public.
- Rankings measure change after tracking starts. They do not establish that AI caused the savings.

## Information still required before application/deployment

1. Owner-confirmed publisher/business details and commercial eligibility.
2. Chosen hosting account, region and approved monthly budget; production HTTPS API origin.
3. Hosted privacy/support pages and provider-approved user disclosures. Current privacy text is a draft.
4. Exact provider callback: `https://<approved-api-host>/callback` (placeholder only; not registered).
5. Enable Banking production application ID and signing key, supplied through the chosen host’s secret manager. Never paste private keys into chat or commit them.
6. Provider-approved retention and backup policy, operational deletion procedures and incident/support ownership.
7. TestFlight verification with real Apple sign-in, bank consent, history import, expiry, reconnection, disconnect and deletion.

Official entry points: https://enablebanking.com/sign-in/ and https://enablebanking.com/docs/api/reference/.
