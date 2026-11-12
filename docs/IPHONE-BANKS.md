# Legacy private iPhone setup (superseded)

The public iPhone interface now uses Continue with Apple and Connect your bank. The manual service configuration described below is retained as historical setup documentation; it is no longer shown in the iPhone app. See [current account onboarding](APP-ACCOUNTS.md).

# Connect existing authorized banks on iPhone

1. Run your existing private Enable Banking service (see `BankSyncService/README.md`). It must be reachable from the iPhone over trusted HTTPS. `localhost` on an iPhone refers to the phone, not your Mac. Never disable certificate verification or expose the raw service without its authentication and HTTPS reverse proxy.
2. In Mochi on iPhone, open Settings → Bank connections → Set up bank connection. Enter the same service URL and connection key used by your Mac. The key is stored in iOS Keychain; do not enter provider private keys or your bank password.
3. Banks already authorized through that service appear after setup. Authorization from an unrelated app or another service cannot be reused this way. Expired bank consent requires approval again.
4. Choose the import start date. For an empty ledger, select at least three months ago to populate the historical coach, subject to bank history availability. For a ledger with statement imports, choose after those imports: records without matching stable bank IDs can overlap.
5. Tap Sync now. Completed payments are merged atomically, using stable bank IDs to prevent duplicate live imports. Foreign-currency batches fail without modifying the ledger. The Flow tab immediately recomputes from imported transactions.
6. For another bank, choose it and tap Connect bank. Complete approval in the bank’s browser flow, return to Mochi, refresh connections and sync. The current service lists Belgium and Revolut France; availability depends on the activated provider application.

Automatic checks run about every six hours while the app is active and catch up on reopening. iOS can suspend the app; this does not provide background bank updates. User-edited transactions and goals remain local to each device.

Disconnect revokes the shared service’s sessions, including Mac access if it uses that service. Imported payments are retained. Deleting local data alone does not revoke authorization, and active sync may import transactions again.

## Public release

This integration is for an existing private single-user service. Do not ship a shared connection key inside an App Store binary. A public product needs user authentication, per-user bank session isolation, appropriate provider production approval, deletion/revocation flows and production privacy/support information before onboarding other users.

## Verification limits

Shared macOS client compilation, iOS syntax parsing, atomic phone ledger import tests and existing provider-service tests are executable here. Full Xcode/iOS SDK, physical-device authorization and a live activated provider application are still needed to verify the complete iPhone flow.
