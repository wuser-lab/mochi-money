import SwiftUI
import Charts

struct CommunityView: View {
    @ObservedObject var sync: BankSync
    let currency: String
    @State private var profile: CommunityProfile?
    @State private var board: CommunityBoard?
    @State private var message: String?
    @State private var busy = false
    @State private var editingPrivacy = false
    @State private var stopping = false
    @State private var showingExample = false
    @State private var month = Self.months.first!
    @State private var country = ""
    private static var months: [String] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.dateInterval(of: .month, for: Date())!.start
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM"
        return (1...12).map { formatter.string(from: calendar.date(byAdding: .month, value: -$0, to: start)!) }
    }
    fileprivate static var countries: [String] { Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }.sorted { countryName($0) < countryName($1) } }
    fileprivate static func countryName(_ code: String) -> String { Locale.current.localizedString(forRegionCode: code) ?? code }
    private func change(_ n: Double) -> String { String(format: "%+.1f pp", n) }
    var body: some View {
        List {
            Section {
                Label("Small steps. Worldwide progress.", systemImage: "globe.europe.africa.fill").font(.headline)
                Text("Compare changes in savings rate after starting a W Money strategy. Percentages make different currencies comparable. Participation is optional and private by default.")
                Text("These are observed changes, not proof that AI caused the savings. Results depend on income and connected account coverage.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Your progress") {
                if sync.accountID == nil {
                    Text("Browse the chart without sharing. To track your own progress, connect a bank in Settings and sign in with Apple.")
                } else if let profile, profile.tracking {
                    Label(profile.sharing ? "Sharing publicly" : "Private • only you can see your progress", systemImage: profile.sharing ? "globe" : "lock.fill")
                    if let rate = profile.baselineRate { LabeledContent("Baseline savings rate", value: String(format: "%.1f%%", rate)) }
                    if let score = profile.score {
                        LabeledContent("Change in \(score.month)", value: change(score.improvement))
                        Text("Updated \(String(score.updatedAt.prefix(10)))").font(.caption)
                    } else if let eligible = profile.eligibleMonth {
                        Text("First comparison: \(eligible), once that whole month is complete and synced. No early estimate is ranked.")
                    }
                    Button("Refresh my progress") { Task { await refreshProgress() } }.disabled(busy)
                    Button("Privacy & public profile") { editingPrivacy = true }.disabled(busy)
                    Button("Stop tracking & remove my result", role: .destructive) { stopping = true }.disabled(busy)
                } else {
                    Text("Track a strategy privately first. We’ll compare three previous full months with a full month after you begin. Three months of bank income history are required.")
                    Button("Start tracking my W Money strategy") { Task { await startTracking() } }.disabled(busy)
                }
            }
            Section("Worldwide comparison") {
                Picker("Month (UTC)", selection: $month) { ForEach(Self.months, id: \.self) { Text($0) } }.disabled(busy)
                Picker("Country", selection: $country) {
                    Text("Worldwide").tag("")
                    ForEach(Self.countries, id: \.self) { Text(Self.countryName($0)).tag($0) }
                }.disabled(busy)
                if let board, !board.entries.isEmpty {
                    Text("Savings-rate improvement • percentage points").font(.caption)
                    SavingsRateChart(entries: board.entries)
                    ForEach(Array(board.entries.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text("\(entry.rank)").monospacedDigit().foregroundStyle(.secondary).frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(entry.nickname).font(.headline)
                                Text(entry.country.map(Self.countryName) ?? "Country private").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(change(entry.improvement)).monospacedDigit()
                        }.accessibilityElement(children: .combine)
                    }
                } else {
                    ContentUnavailableView("No shared results yet", systemImage: "chart.bar.xaxis", description: Text("Only people who explicitly share a completed comparison appear here. No balances or transaction details are public."))
                }
                Text("Ranks use change from each person’s own baseline, not total wealth. Country is self-selected and can stay hidden. Up to 100 results; the chart shows the first 10. Equal scores share a rank.").font(.caption).foregroundStyle(.secondary)
            }
            Section("How this works") {
                Button("Preview an example chart") { showingExample = true }
                Text("Savings rate = (income − spending) ÷ income. A move from 10% to 15% is +5 percentage points. Own-account transfers are excluded. Only synced bank records in one currency and the same connected accounts are compared; manual entries aren’t ranked.").font(.caption)
                Text("You can keep tracking privately, hide your country, withdraw sharing at any time, or delete tracking entirely. Your nickname, optional country, monthly improvement and update date are the only public profile fields.").font(.caption)
            }
            if busy { ProgressView() }
            if let message { Section { Text(message).font(.callout) } }
            Button("Reload comparison") { Task { await loadBoard() } }.disabled(busy)
        }
        .navigationTitle("Worldwide")
        .task(id: sync.accountID) { profile = nil; board = nil; await load() }
        .onChange(of: month) { _, _ in Task { await loadBoard() } }
        .onChange(of: country) { _, _ in Task { await loadBoard() } }
        .sheet(isPresented: $showingExample) {
            NavigationStack {
                List {
                    Section("Illustrative data • not live results") {
                        Text("Fictional savers show how percentage-point improvements compare. These entries are never included in the worldwide ranking.")
                        SavingsRateChart(entries: Self.examples)
                        ForEach(Array(Self.examples.enumerated()), id: \.offset) { _, entry in
                            LabeledContent(entry.nickname + " • " + Self.countryName(entry.country!), value: change(entry.improvement))
                        }
                    }
                }.navigationTitle("Example comparison")
                .toolbar { Button("Done") { showingExample = false } }
            }
        }
        .sheet(isPresented: $editingPrivacy) {
            if let profile { CommunityPrivacy(sync: sync, profile: profile) { updated in self.profile = updated; Task { await loadBoard() } } }
        }
        .confirmationDialog("Delete tracking and remove your public result?", isPresented: $stopping) {
            Button("Stop tracking", role: .destructive) {
                Task {
                    busy = true; defer { busy = false }
                    do { profile = try await sync.stopCommunityTracking(); await loadBoard() } catch { message = error.localizedDescription }
                }
            }
        } message: { Text("Your bank connections and ledger remain. You can start a new baseline later; this comparison history will be removed.") }
    }
    private static var examples: [CommunityEntry] {
        [CommunityEntry(rank: 1, nickname: "Example saver A", country: "BE", improvement: 8, month: "Example", updatedAt: "Example"),
         CommunityEntry(rank: 2, nickname: "Example saver B", country: "JP", improvement: 5, month: "Example", updatedAt: "Example"),
         CommunityEntry(rank: 3, nickname: "Example saver C", country: "BR", improvement: 2, month: "Example", updatedAt: "Example")]
    }
    private func load() async {
        message = nil
        let account = sync.accountID
        if account != nil {
            do {
                let result = try await sync.communityProfile()
                guard account == sync.accountID, !Task.isCancelled else { return }
                profile = result
            } catch { if account == sync.accountID { message = error.localizedDescription } }
        }
        guard account == sync.accountID, !Task.isCancelled else { return }
        await loadBoard()
    }
    private func loadBoard() async {
        let selectedMonth = month, selectedCountry = country
        do {
            let result = try await BankSync.leaderboard(month: selectedMonth, country: selectedCountry.isEmpty ? nil : selectedCountry)
            if selectedMonth == month && selectedCountry == country { board = result; message = nil }
        } catch { if selectedMonth == month && selectedCountry == country { board = nil; message = error.localizedDescription } }
    }
    private func startTracking() async {
        busy = true; message = nil; defer { busy = false }
        let account = sync.accountID
        do {
            let result = try await sync.startCommunityTracking(currency: currency)
            if account == sync.accountID { profile = result }
        } catch { if account == sync.accountID { message = error.localizedDescription } }
    }
    private func refreshProgress() async {
        busy = true; message = nil; defer { busy = false }
        let account = sync.accountID
        do {
            let result = try await sync.refreshCommunityScore()
            guard account == sync.accountID else { return }
            profile = result; await loadBoard()
        } catch {
            guard account == sync.accountID else { return }
            let failure = error.localizedDescription
            profile = try? await sync.communityProfile()
            await loadBoard(); message = failure
        }
    }
}

private struct CommunityPrivacy: View {
    @ObservedObject var sync: BankSync
    let onSave: (CommunityProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sharing: Bool
    @State private var nickname: String
    @State private var country: String
    @State private var busy = false
    @State private var message: String?
    init(sync: BankSync, profile: CommunityProfile, onSave: @escaping (CommunityProfile) -> Void) {
        self.sync = sync; self.onSave = onSave
        _sharing = State(initialValue: profile.sharing); _nickname = State(initialValue: profile.nickname); _country = State(initialValue: profile.country ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Your choice") {
                    Toggle("Share my progress publicly", isOn: $sharing)
                    Text("Off by default. Saving with sharing enabled publishes your nickname, optional country, monthly savings-rate change and update date to everyone who can view the chart. Exact amounts, bank details and transactions stay private.").font(.caption)
                }
                if sharing {
                    Section("Public preview") {
                        Text(nickname).font(.headline)
                        Picker("Country", selection: $country) {
                            Text("Keep country private").tag("")
                            ForEach(CommunityView.countries, id: \.self) { Text(CommunityView.countryName($0)).tag($0) }
                        }
                        Text("\(nickname) • \(country.isEmpty ? "Country private" : CommunityView.countryName(country))")
                        Text("W Money generates this nickname; your Apple name is never used. Country is your choice; we don’t infer location.").font(.caption)
                    }
                }
                if let message { Text(message) }
                Button(sharing ? "Save & share publicly" : "Save as private") {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            let profile = try await sync.saveCommunityPrivacy(sharing: sharing, country: country.isEmpty ? nil : country)
                            onSave(profile); dismiss()
                        } catch { message = error.localizedDescription }
                    }
                }.disabled(busy)
                if busy { ProgressView() }
            }.navigationTitle("Sharing & privacy")
            .toolbar { Button("Cancel") { dismiss() } }
        }.interactiveDismissDisabled(busy)
    }
}

private struct SavingsRateChart: View {
    let entries: [CommunityEntry]
    var body: some View {
        Chart(Array(entries.prefix(10).enumerated()), id: \.offset) { index, entry in
            BarMark(x: .value("Improvement (percentage points)", entry.improvement), y: .value("Saver", "\(index+1). \(entry.nickname)"))
                .foregroundStyle(entry.improvement >= 0 ? Color.accentColor : Color.gray)
                .accessibilityLabel("\(entry.nickname), \(entry.country.map(CommunityView.countryName) ?? "country hidden")")
                .accessibilityValue(String(format: "%+.1f percentage points", entry.improvement))
        }.chartXAxisLabel("Change in percentage points")
            .frame(height: CGFloat(min(10, entries.count) * 42 + 45))
    }
}
