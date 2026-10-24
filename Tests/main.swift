import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let date = ISO8601DateFormatter().date(from: "2026-07-22T12:00:00Z")!
let items = [
    MoneyTransaction(title: "Lunch, with Ana", amount: 18.5, kind: .expense, category: "Food", date: date, note: "Nice \"little\" place"),
    MoneyTransaction(title: "Salary", amount: 3000, kind: .income, category: "Salary", date: date, note: "")
]
let csv = CSVCodec.encode(items)
let decoded = try CSVCodec.decode(csv)
expect(decoded.count == 2, "CSV count")
expect(decoded[0].title == "Lunch, with Ana", "quoted comma")
expect(decoded[0].note == "Nice \"little\" place", "escaped quote")
expect(decoded[1].kind == .income, "kind round trip")
expect(abs(decoded[0].amount - 18.5) < 0.001, "amount round trip")
print("Mochi Money codec tests passed")

let crlf = csv.replacingOccurrences(of: "\n", with: "\r\n")
expect(try! CSVCodec.decode("\u{FEFF}" + crlf).count == 2, "Windows CSV with BOM")
func imported(_ title: String, _ kind: TransactionKind = .expense, _ note: String = "Revolut statement", _ category: String = "Other") -> MoneyTransaction {
    MoneyTransaction(title: title, amount: 10, kind: kind, category: category, date: date, note: note)
}
let source = [
    imported("PAYMENTVIABANCONTACT", .expense, "KBC | COLRUYTLVN3650 | 512788XXXXXX1234 | CARDHOLDER:TESTUSER"),
    imported("PAYMENTVIADEBITMASTERCARD", .expense, "KBC | REVOLUT**5870*IED02R296DUBLIN"),
    imported("Payment from TEST USER", .income),
    imported("Top-up by *1234", .income),
    imported("SENDINGMONEYINSTANTLYTO", .expense, "KBC | USERTEST"),
    imported("Transfer to ANOTHER PERSON"),
    imported("NMBS/SNCB"),
    imported("Premium plan fee"),
    imported("CREDITTRANSFERFROM", .income, "KBC | KATHOLIEKEUNIVERSITEITLEUVEN | /A/BEURS10/2026"),
    imported("ALDI", .expense, "KBC | ALDI", "Shopping")
]
let classified = ImportRules.apply(to: source)
expect(classified[0].category == "Food", "KBC merchant in note")
expect(classified[1...4].allSatisfy { $0.isInternalTransfer == true }, "both own-account transfer directions and card top-ups")
expect(classified[5].isInternalTransfer == false, "payment to someone else stays visible")
expect(classified[6].category == "Transport", "Revolut train")
expect(classified[7].category == "Bills", "bank subscription")
expect(classified[8].category == "Scholarship", "scholarship is not salary")
expect(classified[9].category == "Shopping", "preserve assigned category")
expect(ImportRules.apply(to: classified) == classified, "migration is idempotent")
let exportedTransfers = try CSVCodec.decode(CSVCodec.encode(classified))
expect(ImportRules.apply(to: exportedTransfers)[1].isInternalTransfer == true, "transfer survives CSV export/import")
var overridden = source[2]; overridden.isInternalTransfer = false
expect(ImportRules.apply(to: [source[0], overridden])[1].isInternalTransfer == false, "manual transfer override persists")
print("Import classification tests passed")
