import Foundation

/// Conservative rules for statement imports. Explicit categories remain editable.
enum ImportRules {
    static func apply(to transactions: [MoneyTransaction]) -> [MoneyTransaction] {
        let kbc = transactions.filter { $0.note.hasPrefix("KBC |") }
        let owners = Set(kbc.compactMap { item -> String? in
            guard let part = item.note.components(separatedBy: " | ").first(where: { $0.hasPrefix("CARDHOLDER:") }) else { return nil }
            return compact(String(part.dropFirst("CARDHOLDER:".count)))
        })
        let cards = Set(kbc.flatMap { item in
            item.note.components(separatedBy: " | ").filter { $0.contains("XXXXXX") && $0.count == 16 }.map { String($0.suffix(4)) }
        })
        func isOwner(_ text: String) -> Bool {
            let value = compact(text)
            return owners.contains(value) || owners.contains { owner in
                // Statements reverse surname/given-name order.
                (1..<owner.count).contains { offset in
                    let split = owner.index(owner.startIndex, offsetBy: offset)
                    return String(owner[split...]) + String(owner[..<split]) == value
                }
            }
        }
        return transactions.map { original in
            var item = original
            let parts = item.note.components(separatedBy: " | ")
            let isKBC = item.note.hasPrefix("KBC |")
            let isRevolut = item.note.hasPrefix("Revolut statement")
            if item.isInternalTransfer == nil {
                let ownKBC = isKBC && (parts.contains(where: { isOwner($0) }) ||
                    parts.contains(where: { compact($0).hasPrefix("REVOLUT") }) && item.kind == .expense)
                let ownRevolut = isRevolut && (
                    isOwner(item.title.replacingOccurrences(of: "Payment from ", with: "").replacingOccurrences(of: "To ", with: "")) ||
                    item.kind == .income && (item.title == "Open banking top-up" || cards.contains { item.title == "Top-up by *" + $0 }))
                item.isInternalTransfer = item.category == "Transfer" || ownKBC || ownRevolut
            }
            if item.isInternalTransfer == true { item.category = "Transfer" }
            else if (isKBC || isRevolut) && (item.category == "Other" || item.category.isEmpty) {
                item.category = category(for: item)
            }
            return item
        }
    }

    private static func compact(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func category(for item: MoneyTransaction) -> String {
        let text = compact(item.title + " " + item.note)
        func contains(_ terms: [String]) -> Bool { terms.contains { text.contains($0) } }
        if item.kind == .income {
            if contains(["REFUND", "REIMBURSEMENT"]) { return "Refund" }
            if contains(["BEURS", "SCHOLARSHIP"]) { return "Scholarship" }
            if contains(["SALARY", "PAYROLL"]) { return "Salary" }
            return "Other"
        }
        if contains(["CASHWITHDRAWAL"]) { return "Cash withdrawal" }
        if contains(["ROBOPORTFOLIO", "INVESTMENTACCOUNT", "REVOLUTDIGITALASSETS", "BYBIT"]) { return "Investments" }
        let university = contains(["KATHOLIEKEUNIVERSITEITLEUVEN", "KULEUVEN"])
        // Confirmed university accommodation payments in the imported statements.
        if university && (450...600).contains(item.amount) { return "Housing" }
        if contains(["COLRUYT", "ALDI", "LIDL", "DELHAIZE", "CARREFOUR", "CANTEEN", "LEUCA", "KATHMANDU", "COOP", "MIGROS", "RESTAUR", "BAKERY", "MCDONALD", "UBEREATS", "DESPUYE", "ALMA2", "SPARVESALIUS", "COMPASSGROUP", "JUMBO", "BOULCASSORET"]) { return "Food" }
        if contains(["NMBS", "BLUEMOBILITY", "SNCB", "SBB", "VBZ", "DELIJN", "TRAIN", "FLIXBUS"]) { return "Transport" }
        if contains(["ORANGE", "PLANFEE", "DIGITALOCEAN", "YANDEXPLUS", "LINKEDIN", "ESIMUSAGE"]) { return "Bills" }
        if contains(["PHARM", "APOTHEEK", "DOCTOR", "HOSPITAL", "CHRISTELIJKEMUTUALITEIT", "MUTCM"]) { return "Health" }
        if item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "on" { return "Shopping" }
        if contains(["ACTION2101", "IKEA", "ZARA", "PRIMARK", "AMAZON"]) { return "Shopping" }
        if contains(["SPORTOASE", "CINEMA", "TICKETLIVE", "SPOTIFY"]) { return "Fun" }
        if university { return "Education" }
        if contains(["BOOKINGCOM", "BKGHOTEL", "AIRBNB"]) { return "Travel" }
        return "Other"
    }
}
