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
