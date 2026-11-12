import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { if !condition() { fatalError(label) } }
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
let now = ISO8601DateFormatter().date(from: "2026-11-10T12:00:00Z")!
let date = ISO8601DateFormatter().date(from: "2026-10-12T12:00:00Z")!
func item(_ amount: Double, _ kind: TransactionKind, transfer: Bool = false, currency: String? = "EUR", date: Date = date) -> MoneyTransaction {
    MoneyTransaction(title: "test", amount: amount, kind: kind, category: "Other", date: date, note: "", isInternalTransfer: transfer, currency: currency)
}
let goals = [SavingsGoal(name: "Later", targetAmount: 12000, savedAmount: 0), SavingsGoal(name: "Earlier", targetAmount: 1000, savedAmount: 0, targetDate: now)]
let data = [item(9000,.income), item(3000,.expense), item(500,.income,transfer:true), item(500,.expense,transfer:true), item(10000,.income,currency:"USD"), item(.nan,.expense), item(100000,.income,date:now)]
let r = FlowPlanner.analyze(data, goals: goals, currency: "EUR", cushion: 100, now: now, calendar: cal)
check(r.income == 3000 && r.spending == 1000 && r.available == 1900, "monthly window and currency")
check(r.excluded == 2 && r.transfers == 1000 && r.coverage == 1, "data quality and transfers")
check(r.goals[0].goal.name == "Earlier" && r.goals[0].allocation == 1000 && r.goals[1].allocation == 900, "priority and shared funds")
check(r.goals.reduce(0) { $0 + $1.allocation } <= r.available, "never allocate more than surplus")
let deficit = FlowPlanner.analyze([item(300,.expense)], goals: goals, currency: "EUR", now: now, calendar: cal)
check(deficit.available == 0 && deficit.goals.allSatisfy { $0.allocation == 0 }, "deficit")
let completed = SavingsGoal(name: "Done", targetAmount: 100, savedAmount: 200, targetDate: date)
let empty = FlowPlanner.analyze([], goals: [completed], currency: "EUR", now: now, calendar: cal)
check(empty.coverage == 0 && empty.goals[0].need == 0 && empty.goals[0].overdue, "empty ledger and completed overdue goal")
print("Planner tests passed")
