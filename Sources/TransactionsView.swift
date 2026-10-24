import SwiftUI

struct TransactionsView: View {
    @ObservedObject var store: MoneyStore
    @Binding var showingAdd: Bool
    @State private var query = ""
    @State private var showTransfers = false
    @State private var filter: Filter = .all
    @State private var editing: MoneyTransaction?
    @State private var deleting: MoneyTransaction?

    enum Filter: String, CaseIterable, Identifiable { case all = "All", income = "Income", expenses = "Expenses"; var id: String { rawValue } }

    private var filtered: [MoneyTransaction] {
        store.transactions.filter { item in
            let typeMatches = filter == .all || (filter == .income && item.kind == .income) || (filter == .expenses && item.kind == .expense)
            let queryMatches = query.isEmpty || item.title.localizedCaseInsensitiveContains(query) || item.category.localizedCaseInsensitiveContains(query) || item.note.localizedCaseInsensitiveContains(query)
            return (showTransfers || item.isInternalTransfer != true) && typeMatches && queryMatches
        }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionTitle("Transactions", subtitle: "Every little in and out, neatly remembered.")
                Spacer()
                Toggle("Show transfers", isOn: $showTransfers).toggleStyle(.checkbox)
                Picker("Filter", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 260)
                Button("Add", systemImage: "plus") { showingAdd = true }.monochromeButton()
            }.padding(28)
            Divider().opacity(0.35)
            if filtered.isEmpty {
                EmptyMochi(title: query.isEmpty ? "No transactions yet" : "No matches", message: query.isEmpty ? "Add your first little money moment." : "Try a different search or filter.")
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { item in
                        HStack {
                            TransactionRow(item: item, store: store)
                            Button { editing = item } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).help("Edit")
                            Button { deleting = item } label: { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("Delete")
                        }
                        .listRowBackground(Color.clear)
                        .padding(.horizontal, 12)
                    }
                }
                .listStyle(.inset)
                .searchable(text: $query, prompt: "Search title, category, or note")
            }
            HStack {
                Text("\(filtered.count) transaction\(filtered.count == 1 ? "" : "s")")
                Spacer()
                Text(store.message)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 12)
        }
        .sheet(item: $editing) { TransactionEditor(store: store, editing: $0) }
        .alert("Delete this transaction?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil }
        } message: { Text("This cannot be undone.") }
    }
}

struct TransactionEditor: View {
    @ObservedObject var store: MoneyStore
    let editing: MoneyTransaction?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var amount: Double
    @State private var kind: TransactionKind
    @State private var category: String
    @State private var date: Date
    @State private var note: String
    @State private var isInternalTransfer: Bool

    init(store: MoneyStore, editing: MoneyTransaction? = nil) {
        self.store = store; self.editing = editing
        _title = State(initialValue: editing?.title ?? "")
        _amount = State(initialValue: editing?.amount ?? 0)
        _kind = State(initialValue: editing?.kind ?? .expense)
        _category = State(initialValue: editing?.category ?? "Food")
        _date = State(initialValue: editing?.date ?? Date())
        _note = State(initialValue: editing?.note ?? "")
        _isInternalTransfer = State(initialValue: editing?.isInternalTransfer ?? false)
    }

    private var categories: [String] { (kind == .expense ? MoneyCategories.expenses : MoneyCategories.income) + (category == "Transfer" ? ["Transfer"] : []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(editing == nil ? "Add a money moment" : "Edit transaction").font(.title2.bold())
                    Text("Mochi will keep it tidy.").foregroundStyle(.secondary)
                }
                Spacer(); MochiMascot().scaleEffect(0.58).frame(width: 55, height: 52)
            }
            Picker("Type", selection: $kind) { ForEach(TransactionKind.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, newValue in category = newValue == .expense ? "Food" : "Salary" }
            Form {
                TextField("Title", text: $title, prompt: Text("What was it?"))
                TextField("Amount", value: $amount, format: .number.precision(.fractionLength(2)))
                Picker("Category", selection: $category) { ForEach(categories, id: \.self) { Label($0, systemImage: MoneyCategories.symbol(for: $0)).tag($0) } }
                Toggle("Transfer between my accounts", isOn: $isInternalTransfer)
                DatePicker("Date", selection: $date, displayedComponents: [.date])
                TextField("Note", text: $note, prompt: Text("Optional tiny detail"), axis: .vertical).lineLimit(2...4)
            }.formStyle(.grouped)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(editing == nil ? "Add transaction" : "Save changes") { save() }
                    .monochromeButton().disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || amount <= 0)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26).frame(width: 480)
    }

    private func save() {
        let item = MoneyTransaction(id: editing?.id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount, kind: kind, category: isInternalTransfer ? "Transfer" : (category == "Transfer" ? "Other" : category), date: date, note: note, isInternalTransfer: isInternalTransfer)
        if editing == nil { store.add(item) } else { store.update(item) }
        dismiss()
    }
}
