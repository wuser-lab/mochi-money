# Bank sync setup

Mochi Money can import booked bank payments through a private Enable Banking
connection service. This directory contains a working, single-user service for
Node.js 22 or newer, with no external packages. It does not create an Enable
Banking account or grant access to a bank automatically.

## What you need

1. An [Enable Banking account](https://enablebanking.com/sign-in/).
2. A registered application, its Application ID, and its RSA private key. Start
   with a sandbox application; live access requires production activation and
   the provider's own-account whitelisting or commercial approval. Check current
   eligibility and terms directly with Enable Banking.
3. Register the exact redirect URL `https://localhost:8787/callback` for a local
   service. For a private server, use `https://YOUR-SERVICE/callback` instead.
   Confirm the redirect is accepted in the provider control panel.
4. Approve account-information access in each bank's browser flow. The available
   bank list is fetched from the provider for Belgium; KBC/Revolut availability
   must be verified with your activated application, not assumed from a mock.

The official [API reference](https://enablebanking.com/docs/api/reference/)
explains application registration, certificates, personal accounts, consent,
and bank-specific access limits. Bank passwords are never entered in Mochi.

## Run a local service

Keep the provider key and state folder outside this repository. Do not put keys,
connection tokens, session files, or bank exports in GitHub. Use a dedicated
Enable Banking application for this service.

Generate a random connection key with `openssl rand -hex 32`, then configure the
following variables in a private environment file readable only by your user.
Do not paste real credentials into a chat or commit that environment file.

```sh
ENABLE_BANKING_APP_ID=YOUR_APPLICATION_ID
ENABLE_BANKING_KEY_FILE=/absolute/private/path/private.pem
MOCHI_SYNC_TOKEN=YOUR_RANDOM_CONNECTION_KEY
MOCHI_SYNC_ORIGIN=https://localhost:8787
MOCHI_SYNC_DATA_DIR=/absolute/private/path/mochi-bank-state
PORT=8787
MOCHI_TLS_CERT_FILE=/absolute/private/path/localhost-cert.pem
MOCHI_TLS_KEY_FILE=/absolute/private/path/localhost-key.pem
```

Enable Banking production registration requires an HTTPS callback. For local
use, provide a localhost certificate trusted by macOS with SAN entries for
localhost and 127.0.0.1, plus its private key using the TLS variables above.
Adding certificate trust requires the Mac owner's approval. Do not bypass
browser certificate warnings or disable TLS verification. If using a reverse
proxy with a publicly trusted HTTPS certificate, omit the two TLS variables.

After exporting those variables, start the service:

```sh
node BankSyncService/server.mjs
```

The process binds to `127.0.0.1`, never all network interfaces. Keep it running
while using sync. For a hosted service, run it behind an HTTPS reverse proxy,
set `MOCHI_SYNC_ORIGIN` to its external HTTPS origin, and preserve that origin's
Host header. This service supports one user only; do not share its connection
key. It is not a multi-user hosted product.

## Connect Mochi Money

Open **Settings → Bank connections → Configure connection**. Enter the service
address and its connection key. Mochi saves that key in macOS Keychain.

Choose a bank from the live list, click **Connect bank**, and complete the bank
consent flow in your browser. Only you should accept provider terms and approve
bank access. Return to Mochi Money afterward. Repeat for your other bank.

**Import payments from** defaults to the day after the latest existing statement
transaction (or today for a new ledger). Keep this after your imported history to
avoid overlap: PDF/legacy CSV entries do not have the provider's stable IDs, so
Mochi cannot reliably match them to live records. Moving the date backward may
create duplicates of those old file imports.

After connecting, automatic sync is enabled. It checks about every six hours
while Mochi is open and your Mac is awake, and catches up when reopened. The
connection service must also be running. **Sync now** requests a manual refresh;
the service reuses a successful response for five minutes to avoid rapid repeat
bank requests. This is not an instant notification system and does not run while
the app is closed. Expired permission requires reconnecting through the bank.

Only booked transactions are imported. Stable entry references prevent duplicate
live imports, including across renewed sessions. Missing stable references or
unfinished pagination fail the sync without committing partial results. Pending,
rejected, and cancelled transactions are excluded. Mixed-currency syncs stop
without changing your ledger: currency conversion is not implemented. Existing
bank transactions can receive corrected amounts and dates; manual titles,
categories, and explicit transfer choices are retained.

Self-transfers are identified by comparing counterparty IBANs against the accounts
authorized through this service. Connect both accounts for this to work. Transfers
stay in the ledger but are hidden from spending and the default activity list.
No bank balance API is requested: the dashboard remains a transaction-ledger
balance, which may differ from the bank's available balance.

**Disconnect** revokes active and superseded provider sessions and stops automatic
sync; already imported transactions are kept. If revocation fails, the UI reports
it and can retry. You can also revoke consent directly at the bank.

## Security and verification

The provider's private key stays in the private service, not in the distributed
app. Session state is encrypted with AES-256-GCM using a key derived from the
connection token and written with owner-only permissions. Preserve that token
across service restarts; changing it prevents decrypting existing sessions.
Callback state is random, expires after 15 minutes, and is single-use. Provider
requests verify TLS, and the native app refuses credential-bearing redirects.
The service has no payment-initiation route and requests transaction access only.

Run the service tests:

```sh
node --test BankSyncService/server.test.mjs
```

These use simulated provider responses and no real bank access. A successful mock
test does not prove live bank compatibility. Before enabling production use,
complete a sandbox authorization and sync, then verify your live accounts after
provider activation. Production setup and real bank consent are still required.
