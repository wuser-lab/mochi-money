import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("money.json")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let now = Date()
let calendar = Calendar.current
let stored = StoredData(
    transactions: [
        MoneyTransaction(title: "Monthly salary", amount: 3400, kind: .income, category: "Salary", date: now, note: ""),
        MoneyTransaction(title: "Apartment", amount: 1050, kind: .expense, category: "Housing", date: now, note: ""),
        MoneyTransaction(title: "Market groceries", amount: 76.40, kind: .expense, category: "Food", date: now.addingTimeInterval(-86400), note: ""),
        MoneyTransaction(title: "Train pass", amount: 49, kind: .expense, category: "Transport", date: now.addingTimeInterval(-172800), note: ""),
        MoneyTransaction(title: "Design work", amount: 420, kind: .income, category: "Freelance", date: now.addingTimeInterval(-259200), note: ""),
        MoneyTransaction(title: "Cinema night", amount: 28, kind: .expense, category: "Fun", date: now.addingTimeInterval(-345600), note: "")
    ],
    budgets: [Budget(category: "Food", monthlyLimit: 350), Budget(category: "Fun", monthlyLimit: 180), Budget(category: "Transport", monthlyLimit: 120)],
    goals: [SavingsGoal(name: "Japan trip", targetAmount: 2500, savedAmount: 780, targetDate: calendar.date(byAdding: .month, value: 8, to: now))],
    currencyCode: "EUR"
)
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(stored).write(to: output, options: .atomic)
print(output.path)
