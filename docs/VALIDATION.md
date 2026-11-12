# Validation

Verified in this development environment:
- Shared Swift planner tests: pass (currency/window filtering, transfers, priority allocation, deficit, empty ledger and completed goals).
- Existing Swift CSV/import/bank merge regressions: pass.
- Existing Node bank service tests: 3 passed.
- Full macOS source compilation with Swift 5 mode and MacOSX26.5.sdk: pass.
- iOS source syntax parsing: pass.
- XcodeGen project generation: pass.
- git diff whitespace check: pass.

Not verified:
- iOS SDK compilation, simulator/device UI, accessibility, archive/signing, TestFlight.
- Live on-device Foundation Models generation/availability and guardrail behavior.
- Visual QA of the added views.

The host's default MacOSX27.2 SDK fails even existing SwiftUI source because its SwiftUIMacros plugin is missing; explicit MacOSX26.5 SDK compilation succeeds. Full Xcode is not installed. Use Xcode 26+ for Foundation Models support. The iOS deployment target is 17; older OS versions retain the deterministic planner with an AI-unavailable explanation.

## iPhone bank connections

- Shared bank client and macOS app compilation against MacOSX26.5.sdk: pass after extracting the BankLedger protocol.
- iOS bank settings and application source syntax parsing: pass.
- PhoneLedger compiled against macOS Foundation/Combine with injected temporary storage: persistence/reload, stable-ID deduplication, mixed-currency rollback, failed-write rollback and unreadable-ledger protection all pass.
- Existing Swift regression/planner suites and all three Node bank-service tests: pass.
- Xcode project regenerated with shared bank client and merge sources.
- iOS SDK type checking, foreground/browser authorization on an iPhone, Keychain behavior on iOS, and live bank imports remain unverified without full Xcode and a configured reachable service.

## Xcode installed: iOS SDK verification

Full Xcode 27.2 is now available. The MochiMoney scheme successfully builds for the generic iOS Simulator destination with the iOS Simulator 27.2 SDK, arm64 and x86_64, without code signing. The app was installed and launched successfully on a dedicated iPhone 17 Pro simulator running iOS 27.0. The project was opened in Xcode.

Visual simulator interaction remains unverified: the computer-use interface could not open the Simulator application. Launch success is a smoke check, not end-to-end UI verification. Physical-device bank authorization, Apple Intelligence output, signing and App Store submission remain pending. Apple Developer enrollment is currently failing for the user's account; no app has been uploaded.

## In-app registration and consumer bank onboarding

Implemented Apple registration, one Connect your bank entry point, user-owned bank sessions and account deletion. Private service URL/key inputs have been removed from the iPhone interface. No hosted API URL or production credentials have been invented or embedded.

Verified:
- Five Node tests pass, including Apple JWT signature/claims, nonce replay, isolated accounts, consent callback ownership and persistence across restart, deletion/revocation, logout, and existing bank-provider protections.
- PhoneLedger tests pass with account switching, sign-out isolation and per-account local deletion.
- Full macOS source compilation passes against MacOSX26.5.sdk.
- Full iOS Simulator build passes with Xcode 27.2.
- Device Hub UI inspection verifies Settings → Connect your bank → in-app Apple registration. The missing-production-configuration state is explicit, and Continue with Apple is disabled until an API origin is configured. No manual service credentials appear.

Not yet verified or activated:
- Real Apple identity/code exchange, signed-device capability configuration, Apple revocation notifications, production provider activation, hosted HTTPS API/secrets, and real bank approval/sync. See APP-ACCOUNTS.md for deployment and release gates.

## Optional worldwide savings comparison

- All 8 Node tests pass, covering account isolation and the new complete-month comparison/consent/public-field checks. API integration tests verify private defaults, opt-out removal, hidden country, generated aliases, tracking deletion and preserving consent across Apple reauthentication.
- Phone ledger persistence/isolation tests pass after adding the client community API methods.
- Full macOS compilation and iOS Simulator build pass.
- Updated the running iPhone simulator and inspected Worldwide: month/country filters, honest empty-service state and the explicitly fictional example chart. Accessibility state confirms the chart values and country labels (Belgium, Japan, Brazil) and its not-live-results heading.
- Live community results remain unavailable until the hosted account/provider service is activated. No real participant data was published during development. Private-account sharing controls are covered through server API tests; real signed-in device testing remains pending activation.

## W Money rebrand and native interface — November 11

- Renamed the iPhone display/product to W Money, added an opaque 1024 × 1024 RGB app icon, preserved bundle/storage identifiers and existing ledger compatibility.
- Redesigned Overview, Activity, Goals and Settings with semantic surfaces, a dark green cash-flow card, mint accents, native controls, adaptive system appearance, editable transactions/goals, a separate temporary sample ledger and a compact planning screen.
- iOS Simulator build and unsigned physical-device Release archive pass. The optional LOCAL_RELEASE archive also passes; this alternative hides unavailable online features and is not enabled in the standard configuration.
- Eight Node account/provider/community tests pass, existing Swift import/bank merge tests pass, planner tests pass. Privacy manifest plist validation and diff whitespace check pass. App icon has no alpha channel.
- Registered the W Money App ID with Sign in with Apple and saved the App Store Connect draft, version 1.1.0, Finance category and listing copy/subtitle.
- Signed archive attempt failed with Xcode's explicit “No Accounts” and missing provisioning-profile errors. No valid code-signing identities are installed. No build was uploaded and no review was requested.
- Mac locked during final native-screen checks. The redesigned simulator layout, sample-ledger interaction, accessibility sizes and final store screenshots still need visual verification after unlocking. Do not describe the redesign as visually QA-complete.
- Production online services, published privacy information, privacy labels, age/content information and final release-scope choice remain release gates; see release/READINESS.md.
