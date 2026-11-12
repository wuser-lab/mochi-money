# W Money online service deployment

Status: prepared plan; no production host, billable service or public API has been created. The owner selected a full online release and confirmed Enable Banking production approval is not yet available.

Use Node 22+ on one instance with persistent private storage behind trusted HTTPS. The current entry point is `node BankSyncService/accounts.mjs`, bound to loopback port 8787. A private reverse proxy must preserve the canonical Host. Do not deploy the legacy shared-token `server.mjs` as the public account service.

Configure the environment documented in `docs/APP-ACCOUNTS.md`. Keep the master encryption key stable across redeployments and recoverable in the secret manager; losing it makes stored records unreadable. Keep the provider private key in a private secret file. Store the Apple client-secret JWT securely and rotate before expiry. Do not place any of these values in the iOS app.

Before deploy:

- Choose a host/account and obtain an explicit spending limit before creating paid storage or services. Render was suggested, but no connected/deployed Render service is confirmed.
- Use a persistent disk with owner-only access, an encrypted backup and a tested recovery/deletion procedure. The filesystem service supports a single process only; horizontal scaling requires a database and shared locking/limits.
- Configure HTTPS, bounded requests, timeouts and trusted-edge per-client rate limits. The application intentionally ignores forwarded IP headers. Redact authorization values, cookies, request bodies and callback query strings from logs.
- Register the provider callback `/callback` and Apple server notification endpoint `/auth/apple/notifications` on the canonical API origin.
- Set `MOCHI_API_BASE_URL` to that tested HTTPS origin when building the final app. It is intentionally empty in the uploaded preparation build.
- Exercise full sign-in and account lifecycle with real devices/provider access. Confirm bank coverage, account isolation, replay rejection, consent expiry and revocation, deletion, private tracking and public opt-out.
- Publish accurate privacy/support pages and complete App Store privacy disclosures and review information before submission.

A managed host that requires binding `0.0.0.0:$PORT` needs an explicit entry-point adaptation. The current loopback configuration must not be represented as a ready-to-run Render blueprint. Production monitoring and durable cleanup retries also need operational verification before launch.
