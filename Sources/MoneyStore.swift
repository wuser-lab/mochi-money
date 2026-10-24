import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MoneyStore: ObservableObject {
    @Published private(set) var transactions: [MoneyTransaction] = []
    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var goals: [SavingsGoal] = []
    @Published var currencyCode = "EUR" { didSet { save() } }
    @Published var message = "Your money is tucked in safely."

    private let dataURL: URL
    private let calendar = Calendar.current

    init() {
        let folder: URL
        if let override = ProcessInfo.processInfo.environment["MOCHI_MONEY_DATA_DIR"], !override.isEmpty {
            folder = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            folder = support.appendingPathComponent("MochiMoney", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        dataURL = folder.appendingPathComponent("money.json")
        load()
    }

    var visibleTransactions: [MoneyTransaction] { transactions.filter { $0.isInternalTransfer != true } }

    var totalIncome: Double { visibleTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    var totalExpenses: Double { visibleTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
    var balance: Double {
        let amount = transactions.reduce(0) { $0 + ($1.kind == .income ? $1.amount : -$1.amount) }
        return abs(amount) < 0.005 ? 0 : amount
    }

    var monthTransactions: [MoneyTransaction] {
        visibleTransactions.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }
    var monthIncome: Double { monthTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    var monthExpenses: Double { monthTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }

    var monthCategorySpending: [(category: String, amount: Double)] {
        let grouped = Dictionary(grouping: monthTransactions.filter { $0.kind == .expense }, by: \.category)
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }.sorted { $0.amount > $1.amount }
    }

    func spent(in category: String) -> Double {
        monthTransactions.filter { $0.kind == .expense && $0.category == category }.reduce(0) { $0 + $1.amount }
    }

    func add(_ item: MoneyTransaction) {
        transactions.append(item); save(); message = "Added \(item.title). Tiny win!"
    }

    func update(_ item: MoneyTransaction) {
        guard let index = transactions.firstIndex(where: { $0.id == item.id }) else { return }
        transactions[index] = item; save(); message = "Transaction updated."
    }

    func delete(_ item: MoneyTransaction) {
        transactions.removeAll { $0.id == item.id }; save(); message = "Transaction removed."
    }

    func addBudget(category: String, limit: Double) {
        if let index = budgets.firstIndex(where: { $0.category == category }) {
            budgets[index].monthlyLimit = limit
        } else { budgets.append(Budget(category: category, monthlyLimit: limit)) }
        save(); message = "Budget ready for \(category)."
    }

    func deleteBudget(_ budget: Budget) { budgets.removeAll { $0.id == budget.id }; save() }

    func addGoal(name: String, target: Double, saved: Double, date: Date?) {
        goals.append(SavingsGoal(name: name, targetAmount: target, savedAmount: saved, targetDate: date))
        save(); message = "New goal planted."
    }

    func updateGoal(_ goal: SavingsGoal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[index] = goal; save(); message = "Goal progress updated."
    }

    func deleteGoal(_ goal: SavingsGoal) { goals.removeAll { $0.id == goal.id }; save() }

    func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f %@", value, currencyCode)
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mochi-money-transactions.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVCodec.encode(transactions).write(to: url, atomically: true, encoding: .utf8)
            message = "CSV exported successfully."
        } catch { message = "Export failed: \(error.localizedDescription)" }
    }

    func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try CSVCodec.decode(String(contentsOf: url, encoding: .utf8))
            transactions = ImportRules.apply(to: transactions + imported); save(); message = "Imported \(imported.count) transactions."
        } catch { message = "Import failed: \(error.localizedDescription)" }
    }

    func addDemoData() {
        let now = Date()
        transactions = [
            MoneyTransaction(title: "Monthly salary", amount: 3400, kind: .income, category: "Salary", date: now, note: ""),
            MoneyTransaction(title: "Apartment", amount: 1050, kind: .expense, category: "Housing", date: now, note: ""),
            MoneyTransaction(title: "Market groceries", amount: 76.40, kind: .expense, category: "Food", date: now.addingTimeInterval(-86400), note: ""),
            MoneyTransaction(title: "Train pass", amount: 49, kind: .expense, category: "Transport", date: now.addingTimeInterval(-172800), note: ""),
            MoneyTransaction(title: "Design work", amount: 420, kind: .income, category: "Freelance", date: now.addingTimeInterval(-259200), note: ""),
            MoneyTransaction(title: "Cinema night", amount: 28, kind: .expense, category: "Fun", date: now.addingTimeInterval(-345600), note: "")
        ]
        budgets = [Budget(category: "Food", monthlyLimit: 350), Budget(category: "Fun", monthlyLimit: 180), Budget(category: "Transport", monthlyLimit: 120)]
        goals = [SavingsGoal(name: "Japan trip", targetAmount: 2500, savedAmount: 780, targetDate: calendar.date(byAdding: .month, value: 8, to: now))]
        save(); message = "Demo data added. Explore away!"
    }

    func clearAll() {
        transactions = []; budgets = []; goals = []; save(); message = "Fresh start. Everything is clear."
    }

    private func load() {
        guard let data = try? Data(contentsOf: dataURL), let stored = try? JSONDecoder.configured.decode(StoredData.self, from: data) else { return }
        transactions = ImportRules.apply(to: stored.transactions); budgets = stored.budgets; goals = stored.goals; currencyCode = stored.currencyCode
    }

    private func save() {
        let stored = StoredData(transactions: transactions, budgets: budgets, goals: goals, currencyCode: currencyCode)
        guard let data = try? JSONEncoder.configured.encode(stored) else { return }
        try? data.write(to: dataURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var configured: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
private extension JSONDecoder {
    static var configured: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}
