import SwiftUI

struct BudgetsView: View {
    @ObservedObject var store: MoneyStore
    @State private var showingAdd = false
    @State private var editing: Budget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    SectionTitle("Budgets", subtitle: "Kind boundaries for a calmer month.")
                    Spacer(); Button("New budget", systemImage: "plus") { showingAdd = true }.monochromeButton()
                }
                if store.budgets.isEmpty {
                    MochiCard { EmptyMochi(title: "No limits, no pressure", message: "Create a category budget when you are ready.") }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(store.budgets) { budget in
                            BudgetCard(budget: budget, store: store) { editing = budget } onDelete: { store.deleteBudget(budget) }
                        }
                    }
                }
                MochiCard {
                    HStack(spacing: 18) {
                        MochiMascot(mood: .proud).scaleEffect(0.72).frame(width: 74, height: 65)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Budgeting should feel helpful, not punishing.").font(.headline)
                            Text("Mochi only shows progress. No red alarms, no guilt—just useful context.").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }.padding(28)
        }
        .sheet(isPresented: $showingAdd) { BudgetEditor(store: store) }
        .sheet(item: $editing) { BudgetEditor(store: store, editing: $0) }
    }
}

private struct BudgetCard: View {
    let budget: Budget
    @ObservedObject var store: MoneyStore
    let onEdit: () -> Void
    let onDelete: () -> Void
    var spent: Double { store.spent(in: budget.category) }
    var ratio: Double { spent / max(budget.monthlyLimit, 0.01) }
    var body: some View {
        MochiCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label(budget.category, systemImage: MoneyCategories.symbol(for: budget.category)).font(.headline)
                    Spacer()
                    Menu { Button("Edit", action: onEdit); Button("Delete", role: .destructive, action: onDelete) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                }
                Text(store.formatted(spent)).font(.system(size: 27, weight: .bold, design: .rounded))
                Text("of \(store.formatted(budget.monthlyLimit)) this month").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: min(ratio, 1)).tint(.white)
                HStack {
                    Text("\(Int(ratio * 100))% used").font(.caption.weight(.medium))
                    Spacer()
                    Text(spent <= budget.monthlyLimit ? "\(store.formatted(budget.monthlyLimit - spent)) left" : "\(store.formatted(spent - budget.monthlyLimit)) over")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct BudgetEditor: View {
    @ObservedObject var store: MoneyStore
    let editing: Budget?
    @Environment(\.dismiss) private var dismiss
    @State private var category: String
    @State private var limit: Double
    init(store: MoneyStore, editing: Budget? = nil) {
        self.store = store; self.editing = editing
        _category = State(initialValue: editing?.category ?? "Food")
        _limit = State(initialValue: editing?.monthlyLimit ?? 300)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(editing == nil ? "New monthly budget" : "Edit budget").font(.title2.bold())
            Form {
                Picker("Category", selection: $category) { ForEach(MoneyCategories.expenses, id: \.self) { Label($0, systemImage: MoneyCategories.symbol(for: $0)).tag($0) } }
                    .disabled(editing != nil)
                TextField("Monthly limit", value: $limit, format: .number.precision(.fractionLength(2)))
            }.formStyle(.grouped)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save budget") { store.addBudget(category: category, limit: limit); dismiss() }.monochromeButton().disabled(limit <= 0) }
        }.padding(26).frame(width: 430)
    }
}
