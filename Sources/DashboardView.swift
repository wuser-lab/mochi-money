import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: MoneyStore
    @Binding var showingAdd: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    SectionTitle("Hello, saver.", subtitle: "A gentle look at your money this month.")
                    Spacer()
                    Text(Date.now.formatted(.dateTime.month(.wide).year()))
                        .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
                summary
                HStack(alignment: .top, spacing: 18) {
                    spendingChart
                    budgetPulse
                }
                recent
            }
            .padding(28)
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            MetricCard(title: "ALL-TIME BALANCE", value: store.formatted(store.balance), symbol: "wallet.bifold.fill", emphasized: true)
            MetricCard(title: "INCOME THIS MONTH", value: store.formatted(store.monthIncome), symbol: "arrow.down.left")
            MetricCard(title: "SPENT THIS MONTH", value: store.formatted(store.monthExpenses), symbol: "arrow.up.right")
            MochiCard {
                VStack(alignment: .leading, spacing: 10) {
                    MochiMascot(mood: store.monthExpenses <= store.monthIncome ? .proud : .calm).scaleEffect(0.58).frame(height: 48)
                    Text(store.monthExpenses <= store.monthIncome ? "Looking cozy" : "Tiny reset time")
                        .font(.headline)
                    Text(store.monthExpenses <= store.monthIncome ? "You're spending within this month's income." : "Expenses are ahead of income this month.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var spendingChart: some View {
        MochiCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("SPENDING BY CATEGORY").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
                if store.monthCategorySpending.isEmpty {
                    EmptyMochi(title: "Nothing spent yet", message: "Your month is a beautifully blank page.")
                } else {
                    Chart(store.monthCategorySpending.prefix(6), id: \.category) { item in
                        BarMark(x: .value("Amount", item.amount), y: .value("Category", item.category))
                            .foregroundStyle(.white)
                            .cornerRadius(5)
                    }
                    .chartXAxis { AxisMarks(position: .bottom) { _ in AxisGridLine().foregroundStyle(.white.opacity(0.06)); AxisValueLabel() } }
                    .chartYAxis { AxisMarks { _ in AxisValueLabel() } }
                    .frame(height: 225)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var budgetPulse: some View {
        MochiCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("BUDGET PULSE").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "heart.fill")
                }
                if store.budgets.isEmpty {
                    EmptyMochi(title: "No budgets yet", message: "Give your spending a few soft boundaries.")
                } else {
                    ForEach(store.budgets.prefix(4)) { budget in
                        let spent = store.spent(in: budget.category)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Label(budget.category, systemImage: MoneyCategories.symbol(for: budget.category))
                                Spacer()
                                Text("\(store.formatted(spent)) / \(store.formatted(budget.monthlyLimit))").font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(spent / max(budget.monthlyLimit, 0.01), 1))
                                .tint(spent > budget.monthlyLimit ? .gray : .white)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }.frame(minHeight: 257, alignment: .top)
        }
        .frame(width: 340)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT ACTIVITY").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Button("Add new", systemImage: "plus") { showingAdd = true }.buttonStyle(.borderless)
            }
            if store.transactions.isEmpty {
                MochiCard { EmptyMochi(title: "Your wallet is quiet", message: "Add an income or expense and Mochi will keep it safe.") }
            } else {
                MochiCard {
                    VStack(spacing: 0) {
                        ForEach(Array(store.transactions.sorted(by: { $0.date > $1.date }).prefix(6)).indices, id: \.self) { index in
                            let item = store.transactions.sorted(by: { $0.date > $1.date })[index]
                            TransactionRow(item: item, store: store)
                            if index < min(store.transactions.count, 6) - 1 { Divider().opacity(0.22) }
                        }
                    }
                }
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String
    var emphasized = false
    var body: some View {
        MochiCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text(title).font(.caption2.bold()).tracking(0.8).foregroundStyle(emphasized ? .black.opacity(0.58) : .secondary); Spacer(); Image(systemName: symbol) }
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(emphasized ? .black : .white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(emphasized ? -2 : 0)
        }
        .background(emphasized ? RoundedRectangle(cornerRadius: 18).fill(.white) : nil)
    }
}

struct TransactionRow: View {
    let item: MoneyTransaction
    @ObservedObject var store: MoneyStore
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.09))
                Image(systemName: MoneyCategories.symbol(for: item.category)).foregroundStyle(.white)
            }.frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.body.weight(.semibold))
                Text("\(item.category) · \(item.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text((item.kind == .expense ? "−" : "+") + store.formatted(item.amount))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(item.kind == .income ? .white : .secondary)
        }.padding(.vertical, 10)
    }
}
