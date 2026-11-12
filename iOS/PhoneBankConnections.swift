import SwiftUI
import AuthenticationServices

struct PhoneBankConnections: View {
    @ObservedObject var sync: BankSync
    @State private var connecting = false
    @State private var disconnecting = false
    @State private var deleting = false
    @State private var error: String?
    var body: some View {
        Section("Your banks") {
            Label(sync.accountID == nil ? "A little less admin. A clearer money plan." : "Your W Money account", systemImage: "building.columns")
            Text("Securely import your payments and keep your goal plan up to date. Your bank handles sign-in; Mochi never sees your bank password.").font(.caption)
            ForEach(sync.connectedBanks, id: \.self) { Label($0, systemImage: "checkmark.circle") }
            Button { connecting = true } label: {
                Label(sync.connectedBanks.isEmpty ? "Connect your bank" : "Connect another bank", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).tint(WStyle.accent).disabled(sync.busy)
            if sync.accountID != nil {
                Toggle("Keep payments in sync", isOn: $sync.automatic).disabled(sync.busy)
                Text("Syncs while Mochi is open and catches up when you return. Your bank may occasionally ask you to approve access again.").font(.caption)
                Button("Sync now") { Task { await sync.sync() } }.disabled(sync.busy || sync.connectedBanks.isEmpty)
                if let date = sync.lastSync { Text("Last synced \(date.formatted())").font(.caption) }
                DisclosureGroup("Import history") {
                    DatePicker("Import from", selection: $sync.startDate, in: ...Date(), displayedComponents: .date)
                    Text("Choose after any statement imports to avoid overlapping records. Bank history availability varies.").font(.caption)
                }.disabled(sync.busy)
                Button("Disconnect banks", role: .destructive) { disconnecting = true }.disabled(sync.busy || sync.connectedBanks.isEmpty)
                Button("Sign out") { Task { do { try await sync.endAccount(delete: false) } catch { self.error = error.localizedDescription } } }.disabled(sync.busy)
                Button("Delete W Money account", role: .destructive) { deleting = true }.disabled(sync.busy)
            }
            if sync.busy { ProgressView() }
            if !sync.message.isEmpty && sync.accountID != nil { Text(sync.message).font(.caption) }
            if sync.accountID == nil {
                Text("Continue with Apple when connecting your first bank. You can also keep using W Money without an account.").font(.caption)
            }
        }
        .sheet(isPresented: $connecting) { BankOnboarding(sync: sync) }
        .confirmationDialog("Disconnect your banks?", isPresented: $disconnecting) {
            Button("Disconnect banks", role: .destructive) { Task { await sync.disconnect() } }
        } message: { Text("Revokes your bank connections on all signed-in devices. Imported payments remain in your ledger.") }
        .confirmationDialog("Delete your W Money account?", isPresented: $deleting) {
            Button("Delete account", role: .destructive) {
                Task { do { try await sync.endAccount(delete: true) } catch { self.error = error.localizedDescription } }
            }
        } message: { Text("Permanently deletes your server account, revokes Apple and bank access, and removes this account’s ledger from this device. Local records on other devices must be deleted there separately.") }
        .alert("W Money", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}

private struct BankOnboarding: View {
    @ObservedObject var sync: BankSync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    @State private var challenge: BankSync.SignInChallenge?
    @State private var error: String?
    @State private var loading = false
    @State private var query = ""
    @State private var started = false
    var body: some View {
        NavigationStack {
            Group {
                if sync.needsSignIn {
                    VStack(spacing: 24) {
                        Image(systemName: "leaf.circle.fill").font(.system(size: 64))
                        Text("Your money, a little calmer.").font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text("Create your W Money account with Apple, then choose your bank and approve read-only payment access. Your local ledger stays separate from other W Money accounts.").multilineTextAlignment(.center)
                        SignInWithAppleButton(.continue) { request in
                            request.nonce = challenge?.nonce
                            request.requestedScopes = []
                        } onCompletion: { result in
                            Task { await complete(result) }
                        }.signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black).frame(height: 52).disabled(challenge == nil || loading)
                        if loading { ProgressView() }
                        if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
                        if error != nil { Button("Try again") { Task { await prepare() } }.disabled(loading) }
                        Text("No bank login details are stored in W Money. You can disconnect your bank or delete your account in Settings.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }.padding(24)
                } else {
                    List {
                        Section {
                            Text("Choose your bank. We’ll open its secure approval page, then import your payments when you return.")
                            if started {
                                Label("Finish approval at your bank, then return here.", systemImage: "arrow.up.forward.app")
                                Button("I’ve approved access") { Task { await finishBank() } }.disabled(sync.busy)
                            }
                        }
                        ForEach(sync.banks.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.country.localizedCaseInsensitiveContains(query) }) { bank in
                            Button {
                                started = true
                                Task { if !(await sync.connect(bank)) { started = false } }
                            } label: {
                                HStack { Label(bank.name, systemImage: "building.columns"); Spacer(); Text(bank.country).foregroundStyle(.secondary); Image(systemName: "chevron.right") }
                            }.disabled(sync.busy)
                        }
                        if sync.banks.isEmpty {
                            Text("No banks loaded yet.")
                            Button("Reload banks") { Task { await sync.refresh() } }.disabled(sync.busy)
                        }
                        Section { Text(sync.message).font(.caption); if sync.busy { ProgressView() } }
                    }.searchable(text: $query, prompt: "Find your bank")
                }
            }
            .navigationTitle(sync.needsSignIn ? "Welcome to W Money" : "Connect your bank")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task(id: sync.needsSignIn) {
                if sync.needsSignIn { await prepare() } else { await sync.refresh() }
            }
            .onChange(of: phase) { _, value in
                if value == .active && started { Task { await finishBank() } }
            }
        }
    }
    private func prepare() async {
        loading = true; error = nil; challenge = nil
        defer { loading = false }
        do { challenge = try await sync.prepareSignIn() } catch { self.error = error.localizedDescription }
    }
    private func complete(_ result: Result<ASAuthorization, Error>) async {
        guard let challenge else { error = "Please try signing in again."; return }
        loading = true; self.challenge = nil
        defer { loading = false }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) else { throw BankSyncError.message("Apple sign-in was not completed.") }
            try await sync.finishSignIn(challenge: challenge.challenge, identityToken: token, code: code, appleUserID: credential.user)
        } catch { self.error = error.localizedDescription }
    }
    private func finishBank() async {
        await sync.refresh()
        guard !sync.awaitingAuthorization, !sync.connectedBanks.isEmpty else { return }
        // Consent can take a moment to arrive. sync checks authorization again.
        let previous = sync.lastSync
        await sync.sync()
        if sync.lastSync != nil && sync.lastSync != previous { dismiss() }
    }
}
