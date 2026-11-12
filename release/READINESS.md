# W Money App Store release — November 12, 2026

## Completed

- Native W Money branding, four-tab SwiftUI interface, cash-flow and spending charts, editable activity and goals, CSV import/export, adaptive colors and a separate sample ledger.
- The local planner estimates goal contributions from completed months. Optional explanations use Apple Foundation Models on supported devices. No remote AI service is configured and no money moves automatically.
- The local-only build keeps banking onboarding, automatic synchronization, online account creation and worldwide rankings disabled.
- Privacy manifest and encryption export settings are included. The app does not send account or transaction data to the developer.
- Build 1.1.0 (2) includes safer local saves/imports, labels in the goal editor, deletion confirmation and a fixed currency while saved records exist. The signed Release archive and App Store package were created successfully. The package upload completed successfully; confirm Apple’s processing status in App Store Connect.
- iPhone 17 Pro overview and goals captures: `release/screenshots/iphone/` (1206 × 2622).
- iPad Pro 13-inch overview and goals captures: `release/screenshots/ipad/` (2064 × 2752).
- Public landing, privacy and support pages are live at `https://wuser-lab.github.io/mochi-money/`. Support email shown publicly: `wmoneyw@proton.me`.

## App Store status

App: W Money, version 1.1.0, build 2. The app record remains in Prepare for Submission until the listing is completed and submitted for review. It is not publicly available yet.

Remaining App Store Connect work:

1. Verify build 2 processing completed.
2. Complete app privacy, age rating, content rights, price/availability and reviewer contact fields.
3. Add the privacy/support URLs and iPhone/iPad screenshots, select build 2 and submit for App Review.
4. Track Apple’s review decision and release status.

The user authorized submitting the local-only release. App Store submission is separate from Apple approval and public availability.

## Online services intentionally excluded

The owner asked to keep online banking paused. No bank provider, hosted account service, Apple web-auth backend, financial-data sync or worldwide community ranking is activated for this release. Do not enable these services as part of the local App Store submission.

The app’s local features include Overview, Activity, Goals, CSV and the on-device planning flow. See `APP-STORE-COPY.md` for listing copy and reviewer instructions.
