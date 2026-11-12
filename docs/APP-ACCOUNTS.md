# In-app accounts and bank onboarding

## Customer experience

Settings → Connect your bank → Continue with Apple (first connection only) → choose bank → approve read-only access at the bank → return to Mochi. The app checks consent and imports completed payments into the goal planner. There are no service-address, API-key or connection-key fields in the iPhone interface. People can still use manual entries and CSV without creating an account.

The app cannot skip the bank's account selection, authentication or consent. Those steps are controlled by the bank. An existing authorization in another app is not transferred to Mochi.

Accounts are created on the first verified Apple sign-in. Opaque app sessions are stored in Keychain. Server-side account data and each user's bank sessions are encrypted at rest. Each account has a separate local ledger file; signing out detaches it and returns to the local guest ledger. Guest transactions are not silently copied into a signed-in account. Other devices fetch bank transactions independently; edits and goals do not sync through this backend.

## Implemented backend

`BankSyncService/accounts.mjs` wraps the existing bank provider engine with:
- Server-issued, single-use, five-minute sign-in challenges.
- Apple RS256 signature, issuer, audience, expiry, issued-at and nonce verification against Apple's public keys; authorization-code exchange and matching subject verification.
- Random expiring device session tokens (only hashes persisted), logout, maximum ten device sessions per account.
- Separate bank state per account and a persistent server-owned callback-state router. The provider callback still needs a valid, single-use state token. Caller-supplied user IDs cannot choose another account's bank data.
- Per-account serialization, encrypted account storage, bounded request bodies and basic request throttling.
- In-app deletion that revokes bank sessions and Apple refresh-token access, invalidates account sessions, deletes the account's server records and removes its ledger from the requesting device. A revocation failure is reported for retry. Other devices' local files are not remotely erased.

The legacy desktop private service entry point remains supported. Never configure a public iPhone build against the old shared-key single-user entry point.

## Production activation (owner/developer work)

This is implemented source, not a live hosted registration service. Until a production endpoint is configured, the app clearly says bank connections are unavailable in this build; local features remain usable. No fake authentication or bank connection is shown.

1. Resolve Apple Developer enrollment, enable Sign in with Apple for the bundle ID, configure signing, and create an Apple client secret for the backend. Store keys only in the hosting platform's secret manager. Rotate the Apple client secret before it expires. The app audience and backend APPLE_CLIENT_ID must match.
2. Activate an Enable Banking production application approved for the intended public/commercial use. Confirm countries, banks and account types. The current bank directory remains Belgium plus Revolut France.
3. Host `accounts.mjs` on Node 22+ behind trusted HTTPS, preserving the canonical Host. Keep the process bound to loopback with a reverse proxy. Use persistent private storage and encrypted backups. This filesystem implementation supports ONE process/replica; a transactional database, shared locks and shared limits are required before horizontal scaling.
4. Register the exact shared callback `https://YOUR-API/callback` with Enable Banking. A random, single-use state maps the callback to its owning account in encrypted server storage; a caller cannot select the account through a URL parameter.
5. Configure the API origin at build time through `MOCHI_API_BASE_URL`; it is written to the `MochiAPIBaseURL` Info.plist field. It must be HTTPS. The app contains no master key or provider secret.
6. Publish accurate privacy and support pages, establish provider-required terms and consent disclosures, configure Apple account-revocation notifications, and validate deletion/revocation, real-device login and real-bank consent in TestFlight. The signed Apple notification endpoint `/auth/apple/notifications` is implemented and tested, but must be registered on the primary App ID after HTTPS deployment. It verifies signatures and audience, blocks sessions before provider cleanup, supports retries and replay protection, and removes revoked/deleted accounts. The iPhone also checks Apple credential status before syncing. Live delivery and provider revocation remain release gates.

Required server environment:

```
MOCHI_SYNC_ORIGIN=https://YOUR-API
MOCHI_MASTER_KEY=<at least 32 random bytes encoded base64url; keep stable and backed up>
MOCHI_SYNC_DATA_DIR=/private/persistent/mochi
APPLE_CLIENT_ID=dev.wwwwwwww.mochimoney
APPLE_CLIENT_SECRET=<Apple-generated developer client-secret JWT>
ENABLE_BANKING_APP_ID=<production provider application ID>
ENABLE_BANKING_KEY_FILE=/private/secrets/enable-banking.pem
PORT=8787
```

Start with `node BankSyncService/accounts.mjs`. Do not commit environment values. Configure the reverse proxy to redact Authorization, cookies and callback query strings from logs, limit request sizes and apply appropriate per-client rate limits. The in-process limiter intentionally ignores forwarded client-IP headers; configure limits at the trusted edge.

## Validation

Run `node --test BankSyncService/accounts.test.mjs BankSyncService/server.test.mjs`. Tests use generated RSA keys and simulated Apple/bank services, not real accounts. They verify signature and claim rejection, challenge replay, cross-account callback rejection, account and transaction isolation, encrypted persistence/restart, logout and deletion/revocation. PhoneLedger tests verify local separation and deletion. The simulator build checks the native interface; real Apple sign-in still needs signing and the production configuration above.

References: https://developer.apple.com/documentation/signinwithapple/verifying-a-user and https://enablebanking.com/docs/api/reference/
