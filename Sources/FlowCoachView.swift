import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif
struct FlowCoachView: View {
    let transactions: [MoneyTransaction]
    let goals: [SavingsGoal]
    let currency: String
    @State private var cushion = 100.0
    @State private var explanation = ""
    @State private var busy = false
    var report: FlowReport { FlowPlanner.analyze(transactions, goals: goals, currency: currency, cushion: cushion) }
    func money(_ n: Double) -> String { n.formatted(.currency(code: currency)) }
    var body: some View {
        Form {
            Section("A monthly rhythm") {
                LabeledContent("Average income", value: money(report.income))
                LabeledContent("Average spending", value: money(report.spending))
                HStack { Text("Keep a cushion"); Spacer(); TextField("Monthly cushion", value: $cushion, format: .number).multilineTextAlignment(.trailing).frame(maxWidth: 130) }
                LabeledContent("Available for goals", value: money(report.available))
                DisclosureGroup("How this is calculated") {
                    Text("The last three complete calendar months form your baseline. Missing months count as zero; this month is excluded. This is an estimate, not your account balance.").font(.caption)
                Text("Coverage: \(report.coverage)/3 months. \(report.excluded) invalid or foreign-currency records excluded. Unspecified currencies assumed \(currency).")
                LabeledContent("Own-account transfer volume", value: money(report.transfers))
                Text("Transfer entries are excluded from income and spending. Both sides may appear in the volume.").font(.caption)
                }
            }
            Section("Your goal strategy") {
                Text("Earliest deadline first; undated goals use 12 months. Suggestions only: no money moves.").font(.caption)
                if goals.isEmpty { Text("Add a goal to build your plan.") }
                ForEach(report.goals) { flow in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(flow.goal.name).font(.headline)
                        Text("Set aside \(money(flow.allocation))/month • need \(money(flow.need))/month")
                        if flow.need > flow.allocation { Text("Monthly gap: \(money(flow.need - flow.allocation)). Review optional spending, increase income, or extend the deadline.") }
                        if flow.overdue { Text("Deadline passed. Choose a new date.").foregroundStyle(.orange) }
                    }
                }
            }
            Section("W Intelligence • on device") {
                Text("Explain aggregate figures using Apple Intelligence. No merchant names, notes, account IDs or goal names are included. Generated interpretations may be wrong; check the calculated plan above.").font(.caption)
                Button(busy ? "Thinking…" : "Explain my plan") { Task { await explain() } }.disabled(busy)
                if !explanation.isEmpty { Text(explanation).textSelection(.enabled) }
            }
        }.formStyle(.grouped).navigationTitle("Your plan")
        .onChange(of: report.facts) { _, _ in explanation = "" }
    }
    @MainActor private func explain() async {
        busy = true
        defer { busy = false }
        let facts = report.facts
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                explanation = "AI is unavailable. Enable Apple Intelligence on a supported device. Your calculated plan still works."
                return
            }
            do {
                let session = LanguageModelSession(instructions: "Explain a budgeting plan briefly. Use supplied figures only; do not invent numbers or recommend investments. Mention historical uncertainty and one next step. No guarantees.")
                let result = try await session.respond(to: "Currency \(currency). \(facts)")
                if facts == report.facts { explanation = "AI interpretation:\n" + result.content }
            } catch { explanation = "AI could not generate an explanation. Your calculated plan is still available." }
            return
        }
        #endif
        explanation = "On-device AI needs a supported Apple Intelligence device and OS 26 or later. Your calculated plan works without it."
    }
}
