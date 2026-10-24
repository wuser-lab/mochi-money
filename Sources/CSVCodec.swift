import Foundation

enum CSVCodec {
    static func encode(_ transactions: [MoneyTransaction]) -> String {
        var rows = ["date,type,title,amount,category,note,bank_id,account_id,currency,transfer_override"]
        let formatter = ISO8601DateFormatter()
        for item in transactions.sorted(by: { $0.date < $1.date }) {
            rows.append([
                formatter.string(from: item.date), item.kind.rawValue, item.title,
                String(format: "%.2f", item.amount), item.category, item.note,
                item.bankID ?? "", item.accountID ?? "", item.currency ?? "", item.transferOverride.map(String.init) ?? ""
            ].map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func decode(_ csv: String) throws -> [MoneyTransaction] {
        let rows = parseRows(csv.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: ""))
        let basic = ["date", "type", "title", "amount", "category", "note"]
        let extended = basic + ["bank_id", "account_id", "currency", "transfer_override"]
        guard let header = rows.first, [basic, extended].contains(header.map { $0.lowercased() }) else {
            throw CSVError.invalidHeader
        }
        let formatter = ISO8601DateFormatter()
        return try rows.dropFirst().filter { !$0.allSatisfy(\.isEmpty) }.map { fields in
            guard fields.count == header.count,
                  let date = formatter.date(from: fields[0]),
                  let kind = TransactionKind(rawValue: fields[1]),
                  let amount = Double(fields[3]), amount >= 0 else { throw CSVError.invalidRow }
            return MoneyTransaction(title: fields[2], amount: amount, kind: kind, category: fields[4], date: date, note: fields[5], bankID: fields.count > 6 && !fields[6].isEmpty ? fields[6] : nil, accountID: fields.count > 7 && !fields[7].isEmpty ? fields[7] : nil, currency: fields.count > 8 && !fields[8].isEmpty ? fields[8] : nil, transferOverride: fields.count > 9 ? Bool(fields[9]) : nil)
        }
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else { quoted.toggle() }
            } else if character == "," && !quoted {
                row.append(field); field = ""
            } else if (character == "\n" || character == "\r") && !quoted {
                if character == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" { index += 1 }
                row.append(field); rows.append(row); row = []; field = ""
            } else { field.append(character) }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    enum CSVError: LocalizedError {
        case invalidHeader, invalidRow
        var errorDescription: String? {
            switch self {
            case .invalidHeader: return "The CSV header is not a Mochi Money export."
            case .invalidRow: return "One or more CSV rows could not be read."
            }
        }
    }
}
