import Foundation

struct BankRecord: Decodable {
    var bankID: String
    var accountID: String
    var currency: String
    var title: String
    var amount: Double
    var kind: TransactionKind
    var date: String
    var note: String
    var isInternalTransfer: Bool
}

enum BankMerge {
    static func merge(_ records: [BankRecord], into current: [MoneyTransaction], currency: String) throws -> (items: [MoneyTransaction], added: Int) {
        var items = current
        var indexes = Dictionary(current.enumerated().compactMap { i, item in item.bankID.map { ($0,i) } }, uniquingKeysWith: { a, _ in a })
        let formatter = ISO8601DateFormatter()
        var added = 0
        for record in records {
            guard record.currency == currency else { throw MergeError.currency(record.currency) }
            guard !record.bankID.isEmpty, !record.accountID.isEmpty, record.amount.isFinite, record.amount > 0,
                  let date = formatter.date(from:record.date) else { throw MergeError.invalid }
            if let index = indexes[record.bankID] {
                items[index].amount = record.amount; items[index].date = date; items[index].kind = record.kind
                items[index].isInternalTransfer = items[index].transferOverride ?? record.isInternalTransfer
                if items[index].isInternalTransfer == true {items[index].category = "Transfer"}
                else if items[index].category == "Transfer" {items[index].category = "Other"}
            } else {
                indexes[record.bankID] = items.count
                items.append(MoneyTransaction(title:record.title,amount:record.amount,kind:record.kind,category:record.isInternalTransfer ? "Transfer" : "Other",date:date,note:record.note,isInternalTransfer:record.isInternalTransfer,bankID:record.bankID,accountID:record.accountID,currency:record.currency))
                added += 1
            }
        }
        return (ImportRules.apply(to:items),added)
    }
    enum MergeError: LocalizedError {
        case currency(String), invalid
        var errorDescription: String? {
            switch self {
            case .currency(let code): return "Sync contains \(code) payments. Mochi currently imports only your selected currency; no payments were changed."
            case .invalid: return "A bank payment could not be read. No payments were changed."
            }
        }
    }
}
