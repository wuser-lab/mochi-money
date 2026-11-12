import SwiftUI
import Charts

enum WBuild {
    #if ONLINE_SERVICES && !LOCAL_RELEASE
    static let onlineEnabled = true
    #else
    static let onlineEnabled = false
    #endif
}
enum WStyle {
    static let ink = Color(red: 0.09, green: 0.15, blue: 0.17)
    static let accent = Color(red: 0.10, green: 0.48, blue: 0.42)
    static let mint = Color(red: 0.65, green: 0.93, blue: 0.80)
}
struct WCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
    }
}
struct WTransactionRow: View {
    let item: MoneyTransaction
    let currency: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.isInternalTransfer == true ? "arrow.left.arrow.right" : MoneyCategories.symbol(for: item.category))
                .font(.system(size: 17, weight: .medium)).foregroundStyle(WStyle.accent)
                .frame(width: 44, height: 44).background(WStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                Text(item.isInternalTransfer == true ? "Between your accounts" : item.category).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text((item.kind == .income ? "+" : "−") + item.amount.formatted(.currency(code: item.currency ?? currency)))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(item.date, format: .dateTime.day().month(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }
}
struct WGoalTile: View {
    let goal: SavingsGoal
    let currency: String
    private var progress: Double { min(1, max(0, goal.savedAmount / max(1, goal.targetAmount))) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "flag.checkered").foregroundStyle(WStyle.accent)
                Text(goal.name).font(.headline)
                Spacer()
                Text(progress, format: .percent.precision(.fractionLength(0))).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            ProgressView(value: progress).tint(WStyle.accent)
            HStack {
                Text(goal.savedAmount, format: .currency(code: currency)).font(.title3.weight(.semibold)).monospacedDigit()
                Text("of " + goal.targetAmount.formatted(.currency(code: currency))).font(.caption).foregroundStyle(.secondary)
            }
            if let date = goal.targetDate { Text("By " + date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }
}
struct WOverview: View {
    @ObservedObject var ledger: PhoneLedger
    let onAdd: () -> Void
    let onGoals: () -> Void
    let onSettings: () -> Void
    let onSample: () -> Void
    let isPreview: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var cashSize = 42.0
    private var monthItems: [MoneyTransaction] {
        ledger.data.transactions.filter { $0.isInternalTransfer != true && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) && ($0.currency == nil || $0.currency == ledger.data.currencyCode) }
    }
    private func total(_ kind: TransactionKind) -> Double { monthItems.filter { $0.kind == kind }.reduce(0) { $0+$1.amount } }
    private var categories: [(String, Double)] {
        Dictionary(grouping: monthItems.filter { $0.kind == .expense }, by: \.category)
            .map { ($0.key, $0.value.reduce(0) { $0+$1.amount }) }.sorted { $0.1 > $1.1 }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label(Date(), systemImage: "calendar", format: .dateTime.month(.wide).year())
                            .font(.caption.weight(.medium)).textCase(.uppercase).tracking(1.5)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.title3)
                    }.foregroundStyle(WStyle.mint)
                    if ledger.data.transactions.isEmpty {
                        Text("A clearer view.\nA little more possibility.").font(.system(.largeTitle, design: .rounded).weight(.semibold)).tracking(-1.2)
                        Text("A calm place to understand your spending and make progress toward what matters.").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Monthly cash flow").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                            Text(total(.income)-total(.expense), format: .currency(code: ledger.data.currencyCode))
                                .font(.system(size: cashSize, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1).monospacedDigit().tracking(-1.5)
                            Text("Income minus spending · recorded activity").font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        HStack(spacing: 32) {
                            heroStat("Income", value: total(.income), symbol: "arrow.down.left")
                            heroStat("Spending", value: total(.expense), symbol: "arrow.up.right")
                        }
                    }
                    Button(action: onAdd) {
                        Label("Add transaction", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).tint(WStyle.mint).foregroundStyle(WStyle.ink)
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white).background(LinearGradient(colors: [WStyle.ink, Color(red: 0.12, green: 0.27, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 30))
                if ledger.data.transactions.isEmpty {
                    WCard {
                        Label("Start with one small step", systemImage: "sparkle").font(.headline)
                        Text("Add a payment, import a statement, or explore W Money with a separate sample ledger.").foregroundStyle(.secondary).font(.subheadline)
                        Button("Import a statement", action: onSettings).font(.subheadline.weight(.semibold))
                        if !isPreview { Button("Explore a sample", action: onSample).font(.subheadline.weight(.semibold)) }
                    }
                }
                if !categories.isEmpty {
                    WCard {
                        HStack { Text("Where it went").font(.headline); Spacer(); Text("This month").font(.caption).foregroundStyle(.secondary) }
                        Chart(Array(categories.prefix(5).enumerated()), id: \.offset) { _, entry in
                            BarMark(x: .value("Amount", entry.1), y: .value("Category", entry.0)).foregroundStyle(WStyle.accent.gradient).cornerRadius(4)
                        }.chartXAxis(.hidden).frame(height: CGFloat(min(5, categories.count)*35))
                        Text("Spending in " + ledger.data.currencyCode + ". Transfers between your accounts are excluded.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                WCard {
                    HStack { Text("Your next milestone").font(.headline); Spacer(); Button("See all", action: onGoals).font(.caption.weight(.semibold)) }
                    if let goal = ledger.data.goals.first { WGoalTile(goal: goal, currency: ledger.data.currencyCode) }
                    else {
                        Text("Give your savings a purpose.").font(.title3.weight(.medium))
                        Text("A weekend away, a first home, or a cushion for whatever comes next.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Create a goal", action: onGoals).font(.subheadline.weight(.semibold))
                    }
                }
                NavigationLink {
                    FlowCoachView(transactions: ledger.data.transactions, goals: ledger.data.goals, currency: ledger.data.currencyCode)
                } label: {
                    WCard {
                        HStack(spacing: 16) {
                            Image(systemName: "sparkles").font(.title2).foregroundStyle(WStyle.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("A plan for your money").font(.headline).foregroundStyle(.primary)
                                Text("Find a monthly rhythm for your goals.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                    }
                }.buttonStyle(.plain)
                if !ledger.data.transactions.isEmpty {
                    WCard {
                        Text("Recent activity").font(.headline)
                        ForEach(Array(ledger.data.transactions.sorted { $0.date > $1.date }.prefix(3))) { item in
                            WTransactionRow(item: item, currency: ledger.data.currencyCode)
                        }
                    }
                }
                Label("Your ledger stays on your device.", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 6)
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("W Money")
    }
    private func heroStat(_ title: String, value: Double, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(value, format: .currency(code: ledger.data.currencyCode)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}

private extension Label where Title == Text, Icon == Image {
    init(_ date: Date, systemImage: String, format: Date.FormatStyle) {
        self.init { Text(date, format: format) } icon: { Image(systemName: systemImage) }
    }
}
