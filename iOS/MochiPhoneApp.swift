import SwiftUI
import UniformTypeIdentifiers
import AuthenticationServices

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
@main struct WMoneyApp: App {
    @StateObject private var ledger = PhoneLedger()
    var body: some Scene { WindowGroup { PhoneHome(ledger: ledger).tint(WStyle.accent) } }
}
struct PhoneHome: View {
    @ObservedObject var ledger: PhoneLedger
    var isPreview = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var settings = false
    @State private var adding = false
    @State private var sample: PhoneLedger?
    @State private var sampleFolder: URL?
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                WOverview(ledger: ledger, onAdd: { adding = true }, onGoals: { tab = 2 }, onSettings: { settings = true }, onSample: showSample, isPreview: isPreview)
                    .toolbar { settingsButton }
            }.tabItem { Label("Overview", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack {
                WActivity(ledger: ledger).toolbar { settingsButton; ToolbarItem(placement: .primaryAction) { Button("Add transaction", systemImage: "plus") { adding = true } } }
            }.tabItem { Label("Activity", systemImage: "arrow.left.arrow.right") }.tag(1)
            NavigationStack { WGoals(ledger: ledger).toolbar { settingsButton } }.tabItem { Label("Goals", systemImage: "flag") }.tag(2)
            if WBuild.onlineEnabled { NavigationStack {
                if isPreview { ContentUnavailableView("Sample stays private", systemImage: "globe", description: Text("Sample transactions are never published or included in worldwide rankings.")).navigationTitle("Worldwide") }
                else { CommunityView(sync: ledger.bankSync, currency: ledger.data.currencyCode).toolbar { settingsButton } }
            }.tabItem { Label("Worldwide", systemImage: "globe") }.tag(3) }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !ledger.loadFailed, !isPreview, WBuild.onlineEnabled else { return }
            await ledger.bankSync.checkAppleCredential()
            if !ledger.bankSync.requiresSignIn { await ledger.bankSync.refresh() }
            await ledger.bankSync.run()
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            if !isPreview && WBuild.onlineEnabled { ledger.bankSync.appleCredentialsRevoked() }
        }
        .sheet(isPresented: $settings) { WSettings(ledger: ledger, isPreview: isPreview) }
        .sheet(isPresented: $adding) { WTransactionEditor(ledger: ledger) }
        .fullScreenCover(item: $sample, onDismiss: {
            sample = nil
            if let folder = sampleFolder { try? FileManager.default.removeItem(at: folder) }; sampleFolder = nil
        }) { preview in PhoneHome(ledger: preview, isPreview: true).tint(WStyle.accent) }
        .alert("Your ledger", isPresented: Binding(get: { ledger.error != nil }, set: { if !$0 { ledger.error = nil } })) { Button("OK") { ledger.error = nil } } message: { Text(ledger.error ?? "") }
    }
    @ToolbarContentBuilder private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isPreview { Label("Sample", systemImage: "eye").font(.caption).foregroundStyle(.secondary) }
            else { Button("Settings", systemImage: "person.crop.circle") { settings = true }.accessibilityHint("Bank connections, currency, imports and privacy") }
        }
        if isPreview { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }
    private func showSample() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WMoney-sample-" + UUID().uuidString)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { ledger.error = error.localizedDescription; return }
        let preview = PhoneLedger(storageURL: folder.appendingPathComponent("money.json"))
        let calendar = Calendar.current, now = Date()
        var items: [MoneyTransaction] = []
        for offset in 0...3 {
            let day = calendar.date(byAdding: .month, value: -offset, to: now)!
            for (title, amount, kind, category) in [("Monthly salary",3200.0,TransactionKind.income,"Salary"),("Apartment",950.0,.expense,"Housing"),("Groceries",286.0,.expense,"Food"),("Train pass",72.0,.expense,"Transport"),("Coffee & weekends",145.0,.expense,"Fun")] {
                items.append(MoneyTransaction(title: title, amount: amount, kind: kind, category: category, date: day, note: "Sample transaction", currency: "EUR"))
            }
        }
        preview.data = StoredData(transactions: items, goals: [SavingsGoal(name: "Japan, someday soon", targetAmount: 4000, savedAmount: 1650, targetDate: calendar.date(byAdding: .month, value: 8, to: now)), SavingsGoal(name: "A little peace of mind", targetAmount: 6000, savedAmount: 2800)], currencyCode: "EUR")
        sampleFolder = folder; sample = preview
    }
}
struct WActivity: View {
    @ObservedObject var ledger: PhoneLedger
    @State private var search = ""
    @State private var transfers = false
    @State private var editing: MoneyTransaction?
    private var items: [MoneyTransaction] {
        ledger.data.transactions.filter { (transfers || $0.isInternalTransfer != true) && (search.isEmpty || ($0.title+" "+$0.category+" "+$0.note).localizedCaseInsensitiveContains(search)) }.sorted { $0.date > $1.date }
    }
    var body: some View {
        List {
            if items.isEmpty { ContentUnavailableView(search.isEmpty ? "Your story starts here" : "No matching activity", systemImage: "tray", description: Text(search.isEmpty ? "Add your first transaction with the plus button, or import a statement in Settings." : "Try a different title or category.")) }
            ForEach(items) { item in
                Button { editing = item } label: { WTransactionRow(item: item, currency: ledger.data.currencyCode) }.buttonStyle(.plain)
                    .swipeActions { Button("Delete", role: .destructive) { ledger.update { $0.transactions.removeAll { $0.id == item.id } } } }
            }
        }.navigationTitle("Activity").searchable(text: $search, prompt: "Search your activity")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu("Filter", systemImage: "line.3.horizontal.decrease") { Toggle("Include own-account transfers", isOn: $transfers) } } }
            .sheet(item: $editing) { WTransactionEditor(ledger: ledger, editing: $0) }
    }
}
struct WGoals: View {
    @ObservedObject var ledger: PhoneLedger
    @State private var adding = false
    @State private var editing: SavingsGoal?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Make room for what matters.").font(.title2.weight(.semibold)).tracking(-0.6)
                Text("One small contribution at a time.").foregroundStyle(.secondary)
                if ledger.data.goals.isEmpty {
                    WCard {
                        Image(systemName: "flag.checkered").font(.largeTitle).foregroundStyle(WStyle.accent)
                        Text("Every plan starts with a possibility.").font(.title3.weight(.semibold))
                        Text("Choose a name, a target, and a date. W Money will help you find a monthly pace.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Create your first goal") { adding = true }.buttonStyle(.borderedProminent)
                    }
                }
                ForEach(ledger.data.goals) { goal in
                    Button { editing = goal } label: { WCard { WGoalTile(goal: goal, currency: ledger.data.currencyCode) } }.buttonStyle(.plain)
                        .contextMenu { Button("Delete goal", role: .destructive) { ledger.update { $0.goals.removeAll { $0.id == goal.id } } } }
                }
            }.padding(20)
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Goals")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("New goal", systemImage: "plus") { adding = true } } }
            .sheet(isPresented: $adding) { WGoalEditor(ledger: ledger) }.sheet(item: $editing) { WGoalEditor(ledger: ledger, editing: $0) }
    }
}
struct WTransactionEditor: View {
    @ObservedObject var ledger: PhoneLedger
    let editing: MoneyTransaction?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Bool
    @State private var title: String
    @State private var amount: Double
    @State private var kind: TransactionKind
    @State private var category: String
    @State private var date: Date
    @State private var note: String
    @State private var transfer: Bool
    @State private var saveError: String?
    init(ledger: PhoneLedger, editing: MoneyTransaction? = nil) {
        self.ledger = ledger; self.editing = editing
        _title = State(initialValue: editing?.title ?? ""); _amount = State(initialValue: editing?.amount ?? 0)
        _kind = State(initialValue: editing?.kind ?? .expense); _category = State(initialValue: editing?.category ?? "Other")
        _date = State(initialValue: editing?.date ?? Date()); _note = State(initialValue: editing?.note ?? ""); _transfer = State(initialValue: editing?.isInternalTransfer ?? false)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it for?", text: $title)
                    HStack { Text(ledger.data.currencyCode).foregroundStyle(.secondary); TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2))).accessibilityLabel("Amount in " + ledger.data.currencyCode).keyboardType(.decimalPad).focused($focus).font(.title2.weight(.semibold)) }
                    Picker("Type", selection: $kind) { ForEach(TransactionKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                }
                Section("Details") {
                    Picker("Category", selection: $category) { ForEach(kind == .income ? MoneyCategories.income : MoneyCategories.expenses, id: \.self) { Text($0) } }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Add a note", text: $note, axis: .vertical)
                    Toggle("Between my own accounts", isOn: $transfer)
                }
            }.navigationTitle(editing == nil ? "New transaction" : "Edit transaction").navigationBarTitleDisplayMode(.inline)
                .onChange(of: kind) { _, _ in category = "Other" }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !amount.isFinite || amount <= 0 || ledger.loadFailed) }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focus = false } }
                }
                .alert("Couldn’t save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) { Button("OK") { saveError = nil } } message: { Text(saveError ?? "") }
        }
    }
    private func save() {
        var item = editing ?? MoneyTransaction(title: title, amount: amount, kind: kind, category: category, date: date, note: note)
        item.title = title.trimmingCharacters(in: .whitespaces); item.amount = amount; item.kind = kind; item.category = category; item.date = date; item.note = note; item.isInternalTransfer = transfer; item.transferOverride = transfer
        if item.currency == nil { item.currency = ledger.data.currencyCode }
        if ledger.update({ next in
            if let index = next.transactions.firstIndex(where: { $0.id == item.id }) { next.transactions[index] = item } else { next.transactions.append(item) }
        }) { dismiss() } else { saveError = ledger.error; ledger.error = nil }
    }
}
struct WGoalEditor: View {
    @ObservedObject var ledger: PhoneLedger
    let editing: SavingsGoal?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var target: Double
    @State private var saved: Double
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var deleting = false
    @State private var saveError: String?
    @FocusState private var amountFocused: Bool
    init(ledger: PhoneLedger, editing: SavingsGoal? = nil) {
        self.ledger = ledger; self.editing = editing
        _name = State(initialValue: editing?.name ?? ""); _target = State(initialValue: editing?.targetAmount ?? 1000); _saved = State(initialValue: editing?.savedAmount ?? 0)
        _hasDate = State(initialValue: editing?.targetDate != nil); _date = State(initialValue: editing?.targetDate ?? Calendar.current.date(byAdding: .month, value: 6, to: Date())!)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Something to look forward to") {
                    TextField("Goal name", text: $name)
                    LabeledContent("Target (" + ledger.data.currencyCode + ")") {
                        TextField("Target", value: $target, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($amountFocused)
                            .accessibilityLabel("Target in " + ledger.data.currencyCode)
                    }
                    LabeledContent("Already saved") {
                        TextField("Already saved", value: $saved, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($amountFocused)
                            .accessibilityLabel("Already saved in " + ledger.data.currencyCode)
                    }
                }
                Section { Toggle("Set a target date", isOn: $hasDate); if hasDate { DatePicker("Target date", selection: $date, displayedComponents: .date) } }
                if editing != nil { Section { Button("Delete goal", role: .destructive) { deleting = true } } }
            }.navigationTitle(editing == nil ? "New goal" : "Your goal").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            var goal = editing ?? SavingsGoal(name: name, targetAmount: target, savedAmount: saved)
                            goal.name = name.trimmingCharacters(in: .whitespaces); goal.targetAmount = target; goal.savedAmount = saved; goal.targetDate = hasDate ? date : nil
                            if ledger.update({ next in
                                if let index = next.goals.firstIndex(where: { $0.id == goal.id }) { next.goals[index] = goal } else { next.goals.append(goal) }
                            }) { dismiss() } else { saveError = ledger.error; ledger.error = nil }
                        }.fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !target.isFinite || target <= 0 || !saved.isFinite || saved < 0 || ledger.loadFailed)
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { amountFocused = false } }
                }
                .confirmationDialog("Delete this goal?", isPresented: $deleting) {
                    Button("Delete goal", role: .destructive) {
                        guard let editing else { return }
                        if ledger.update({ $0.goals.removeAll { $0.id == editing.id } }) { dismiss() }
                        else { saveError = ledger.error; ledger.error = nil }
                    }
                } message: { Text("This removes the goal from your ledger. It does not move any money.") }
                .alert("Couldn’t save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) { Button("OK") { saveError = nil } } message: { Text(saveError ?? "") }
        }
    }
}
struct WSettings: View {
    @ObservedObject var ledger: PhoneLedger
    let isPreview: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "w.square.fill").font(.system(size: 44)).foregroundStyle(WStyle.accent)
                        VStack(alignment: .leading, spacing: 4) { Text("W Money").font(.title2.weight(.semibold)); Text("A little more clarity.").font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(.vertical, 8)
                }
                if !isPreview && WBuild.onlineEnabled { PhoneBankConnections(sync: ledger.bankSync) }
                Section("Your ledger") {
                    Picker("Currency", selection: Binding(get: { ledger.data.currencyCode }, set: { value in
                        if ledger.canChangeCurrency { ledger.update { $0.currencyCode = value } }
                    })) { ForEach(["EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD", "PLN"], id: \.self) { Text($0) } }.disabled(!ledger.canChangeCurrency)
                    Text(ledger.canChangeCurrency ? "Choose your currency before adding activity or goals." : "Your ledger uses " + ledger.data.currencyCode + ". Currency stays fixed while it contains activity, budgets or goals so amounts aren’t relabeled.").font(.caption).foregroundStyle(.secondary)
                    Button("Import statement", systemImage: "square.and.arrow.down") { importing = true }
                    Button("Export transactions", systemImage: "square.and.arrow.up") { exporting = true }
                    Text("CSV files without bank IDs can create duplicates if imported twice.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    NavigationLink("Your data & privacy") { WPrivacyView() }
                    Button("Erase this local ledger", role: .destructive) { deleting = true }
                }
                Section { Text("W Money · 1.1\nBuilt for a clearer relationship with your money.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center) }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
                .disabled(ledger.loadFailed)
                .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                    switch result { case .success(let url): ledger.importFile(url); case .failure(let error): ledger.error = error.localizedDescription }
                }
                .fileExporter(isPresented: $exporting, document: CSVDocument(text: CSVCodec.encode(ledger.data.transactions)), contentType: .commaSeparatedText, defaultFilename: "w-money-transactions") { result in if case .failure(let error) = result { ledger.error = error.localizedDescription } }
                .confirmationDialog("Erase all local transactions and goals?", isPresented: $deleting) { Button("Erase ledger", role: .destructive) { ledger.update { $0 = StoredData() } } } message: { Text(WBuild.onlineEnabled ? "This cannot be undone. Bank connections stay active and can import payments again. Disconnect banks first if you want to stop imports." : "This cannot be undone. Export your transactions first if you want to keep a copy.") }
        }
    }
}
struct WPrivacyView: View {
    var body: some View {
        List {
            Section("Private by design") { Label("No advertising or tracking", systemImage: "hand.raised"); Text("Your transactions and goals are stored in this app’s protected files. CSV exports contain financial information, so share them with care.") }
            if WBuild.onlineEnabled { Section("Your choice to connect") { Text("Bank connections require your approval. When available, your bank authorizes read-only transaction access through our connection service. Disconnect banks or delete your online account in Settings.") } }
            Section("On-device intelligence") { Text("Optional AI explanations use Apple’s on-device model where available. Raw merchant names, account details and notes are excluded. Calculated figures remain the basis of your plan.") }
            if WBuild.onlineEnabled { Section("Worldwide sharing") { Text("Tracking is private by default. Publishing a result is a separate choice. Only a generated nickname, optional country, monthly improvement and update date can appear publicly. You can withdraw sharing at any time.") } }
            Section("Control your data") { Text(WBuild.onlineEnabled ? "Export your ledger, delete local records or revoke connected accounts whenever you choose. Deleting an online account doesn’t remotely erase files on your other devices." : "Export your transactions or delete local records whenever you choose. Your device backup settings may also affect copies stored by Apple.") }
        }.navigationTitle("Your privacy").navigationBarTitleDisplayMode(.inline)
    }
}
