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
let categories: [(String, String)] = [
    ("KBC | AMAZONBERETAIL", "Shopping"),
    ("KBC | NMBSLEUVENTVM", "Transport"),
    ("KBC | BLUE-MOBILITYNV", "Transport"),
    ("KBC | CHRISTELIJKEMUTUALITEIT", "Health"),
    ("KBC | ALMA2BE3000LEUVEN", "Food"),
    ("KBC | COMPASSGROUPDIEGEM", "Food")
]
for (note, expected) in categories {
    expect(ImportRules.category(for: imported("PAYMENTVIABANCONTACT", .expense, note)) == expected, "merchant category: \(expected)")
}
var rent = imported("SENDINGMONEYINSTANTLYTO", .expense, "KBC | KATHOLIEKEUNIVERSITEITLEUVEN")
rent.amount = 512
expect(ImportRules.category(for: rent) == "Housing", "confirmed campus rent")
rent.amount = 11
expect(ImportRules.category(for: rent) == "Education", "small university payment is not rent")
expect(ImportRules.category(for: imported("CASHWITHDRAWALVIABANCONTACT")) == "Cash withdrawal", "cash stays separate")
expect(ImportRules.category(for: imported("To Robo portfolio")) == "Investments", "investment stays separate")
expect(ImportRules.category(for: imported("Unknown merchant")) == "Other", "do not guess unknown purpose")
print("Expanded categorization tests passed")
expect(ImportRules.category(for: imported("On")) == "Shopping", "On sportswear exact merchant name")
expect(ImportRules.category(for: imported("Unknown payment")) == "Other", "On must not match substrings")
let bankRecord = BankRecord(bankID:"bank-unique-reference",accountID:"account-hash",currency:"EUR",title:"ALDI",amount:12.34,kind:.expense,date:"2026-10-24T12:00:00Z",note:"Bank sync: Test bank",isInternalTransfer:false)
let firstSync = try BankMerge.merge([bankRecord,bankRecord],into:[],currency:"EUR")
expect(firstSync.added == 1 && firstSync.items.count == 1, "deduplicate within bank page")
expect(firstSync.items[0].category == "Food", "categorize live bank merchant")
let secondSync = try BankMerge.merge([bankRecord],into:firstSync.items,currency:"EUR")
expect(secondSync.added == 0 && secondSync.items[0].id == firstSync.items[0].id, "idempotent repeated sync")
var manual = firstSync.items[0]; manual.category = "Shopping"; manual.title = "My edited merchant"; manual.transferOverride = false
var corrected = bankRecord; corrected.amount = 13; corrected.isInternalTransfer = true
let correction = try BankMerge.merge([corrected],into:[manual],currency:"EUR")
expect(correction.items[0].amount == 13 && correction.items[0].category == "Shopping" && correction.items[0].title == "My edited merchant", "preserve manual edits when bank updates amount")
expect(correction.items[0].isInternalTransfer == false, "preserve manual self-transfer override")
var foreign = bankRecord; foreign.currency = "CHF"
do { _ = try BankMerge.merge([foreign],into:firstSync.items,currency:"EUR"); expect(false,"reject mixed currency") } catch {}
var legacy = items[0]; legacy.bankID = "saved-bank-id"; legacy.accountID = "saved-account"; legacy.currency = "EUR"; legacy.transferOverride = false
let bankExport = try CSVCodec.decode(CSVCodec.encode([legacy]))
expect(bankExport[0].bankID == legacy.bankID && bankExport[0].transferOverride == false, "CSV preserves bank deduplication metadata")
let oldCSV = "date,type,title,amount,category,note\n2026-10-24T12:00:00Z,Expense,Groceries,5.00,Food,\n"
expect(try! CSVCodec.decode(oldCSV).count == 1, "six-column exports remain supported")
let oldJSON = "{\"title\":\"Old purchase\",\"amount\":2,\"kind\":\"Expense\",\"category\":\"Food\",\"date\":0,\"note\":\"\",\"id\":\"00000000-0000-0000-0000-000000000001\"}"
expect(try! JSONDecoder().decode(MoneyTransaction.self,from:Data(oldJSON.utf8)).bankID == nil, "old ledgers load without bank metadata")
print("Bank merge and compatibility tests passed")
