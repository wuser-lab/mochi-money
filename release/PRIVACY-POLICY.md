# W Money privacy

Updated November 11, 2026. Publication draft; verify the final deployed configuration before publishing this policy.

W Money helps you understand recorded spending and plan savings goals. Local tracking does not require an account. W Money does not include advertising, advertising identifiers, analytics SDKs or cross-app tracking.

## Information on your device

Transactions, notes, categories, goals and currency settings are stored in the app's local files. App settings use device preferences. The app protects ledger writes with the operating system's file protection. Your device backup settings may also affect copies stored by Apple. CSV export is initiated by you and can contain financial information; you choose where it goes.

## Optional online services

When online bank connections are enabled and you choose to use them, Apple sign-in verifies your account through the connection service. The service stores an opaque account identifier, encrypted Apple authorization data and encrypted bank consent/session data. Your bank and the bank-data provider handle authorization. The app never asks for your bank password. Authorized completed transaction data passes through the connection service and is imported to your ledger. The service may briefly cache responses to avoid repeated bank requests.

Country availability and history depend on the bank-data provider. Online services must be activated before they can be used; the development build's unavailable-service screen does not create an account or import data.

## AI explanations

Optional explanations use Apple's on-device model on supported devices. The app sends aggregate planner figures to that on-device model, excluding raw merchant names, account IDs, notes and goal names. It does not configure a remote AI API.

## Worldwide comparison

Starting strategy tracking is private by default. If you separately choose to share publicly, only a generated nickname, your optional selected country, monthly savings-rate improvement, comparison month, update date and rank can appear. Exact amounts, transactions and private baseline figures are not public. The server retains an encrypted private baseline and the associated comparison data to calculate results. Country is chosen by you; the app does not infer location.

Turning sharing off unlists the result. Deleting tracking removes its stored baseline and profile. Previously public information may have been saved by others.

## Your controls

You can export data, erase the local ledger, disconnect banks, sign out, stop sharing, delete tracking or request deletion of your online account within the app. Account deletion revokes bank and Apple access and removes its server records. It removes that account's ledger from the requesting device; files on other devices must be removed there separately. Bank data can be imported again if you erase a local ledger while leaving bank connections active.

## Retention and security

Local information stays until you remove it or remove the app, subject to device backups. Online authorization records remain until you revoke access or delete the account, subject to provider requirements. Session tokens expire and server records use encryption at rest. Infrastructure operators must apply limited-access logging, retention, backups and deletion procedures before public service activation.

## Support

The release must provide a maintained public support URL and a contact route for privacy requests. These release details must be finalized before this draft becomes the public policy.
