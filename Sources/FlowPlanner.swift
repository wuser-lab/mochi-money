import Foundation
struct GoalFlow: Identifiable {
    let goal: SavingsGoal
    let need: Double
    let allocation: Double
    let overdue: Bool
    var id: UUID { goal.id }
}
struct FlowReport {
    let income: Double
    let spending: Double
    let transfers: Double
    let excluded: Int
    let coverage: Int
    let available: Double
    let goals: [GoalFlow]
    var facts: String {
        "Average monthly income \(income), spending \(spending), available after cushion \(available). Coverage \(coverage)/3 months. Excluded \(excluded) records. " + goals.map { "Goal need \($0.need), allocation \($0.allocation), overdue \($0.overdue)." }.joined(separator: " ")
    }
}
enum FlowPlanner {
    static func analyze(_ items: [MoneyTransaction], goals: [SavingsGoal], currency: String, cushion: Double = 100, now: Date = Date(), calendar: Calendar = .current) -> FlowReport {
        let end = calendar.dateInterval(of: .month, for: now)!.start
        let start = calendar.date(byAdding: .month, value: -3, to: end)!
        let window = items.filter { $0.date >= start && $0.date < end }
        let valid = window.filter { $0.amount.isFinite && $0.amount >= 0 && ($0.currency == nil || $0.currency == currency) }
        let external = valid.filter { $0.isInternalTransfer != true }
        func average(_ kind: TransactionKind) -> Double { external.filter { $0.kind == kind }.reduce(0) { $0 + $1.amount } / 3 }
        let income = average(.income), spending = average(.expense)
        let available = max(0, income - spending - (cushion.isFinite ? max(0, cushion) : 0))
        var remaining = available
        let flows = goals.sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }.map { goal -> GoalFlow in
            let months = goal.targetDate.map { max(1, Double(calendar.dateComponents([.day], from: now, to: $0).day ?? 0) / 30.4375) } ?? 12
            let need = goal.targetAmount.isFinite && goal.savedAmount.isFinite ? max(0, goal.targetAmount - goal.savedAmount) / months : 0
            let allocation = min(remaining, need)
            remaining -= allocation
            return GoalFlow(goal: goal, need: need, allocation: allocation, overdue: goal.targetDate.map { $0 < now } ?? false)
        }
        return FlowReport(income: income, spending: spending, transfers: valid.filter { $0.isInternalTransfer == true }.reduce(0) { $0 + $1.amount }, excluded: window.count - valid.count, coverage: Set(valid.map { calendar.dateInterval(of: .month, for: $0.date)!.start }).count, available: available, goals: flows)
    }
}
