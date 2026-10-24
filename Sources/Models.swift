import Foundation

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense = "Expense"
    case income = "Income"
    var id: String { rawValue }
}

struct MoneyTransaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var amount: Double
    var kind: TransactionKind
    var category: String
    var date: Date
    var note: String
    var isInternalTransfer: Bool? = nil
}

struct Budget: Identifiable, Codable, Hashable {
    var id = UUID()
    var category: String
    var monthlyLimit: Double
}

struct SavingsGoal: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var targetAmount: Double
    var savedAmount: Double
    var targetDate: Date?
}

struct StoredData: Codable {
    var transactions: [MoneyTransaction] = []
    var budgets: [Budget] = []
    var goals: [SavingsGoal] = []
    var currencyCode = "EUR"
}

enum MoneyCategories {
    static let expenses = ["Housing", "Food", "Transport", "Shopping", "Health", "Fun", "Travel", "Bills", "Education", "Cash withdrawal", "Investments", "Other"]
    static let income = ["Salary", "Freelance", "Gift", "Interest", "Refund", "Scholarship", "Other"]

    static func symbol(for category: String) -> String {
        switch category {
        case "Cash withdrawal": return "banknote"
        case "Investments": return "chart.line.uptrend.xyaxis"
        case "Scholarship": return "graduationcap.fill"
        case "Transfer": return "arrow.left.arrow.right"
        case "Housing": return "house.fill"
        case "Food": return "fork.knife"
        case "Transport": return "tram.fill"
        case "Shopping": return "bag.fill"
        case "Health": return "cross.case.fill"
        case "Fun": return "sparkles"
        case "Travel": return "airplane"
        case "Bills": return "bolt.fill"
        case "Education": return "book.fill"
        case "Salary": return "briefcase.fill"
        case "Freelance": return "laptopcomputer"
        case "Gift": return "gift.fill"
        case "Interest": return "percent"
        case "Refund": return "arrow.uturn.backward"
        default: return "circle.grid.2x2.fill"
        }
    }
}
