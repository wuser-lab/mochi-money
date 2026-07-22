import SwiftUI

struct GoalsView: View {
    @ObservedObject var store: MoneyStore
    @State private var showingAdd = false
    @State private var editing: SavingsGoal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    SectionTitle("Savings goals", subtitle: "Big dreams, one soft step at a time.")
                    Spacer(); Button("New goal", systemImage: "plus") { showingAdd = true }.monochromeButton()
                }
                if store.goals.isEmpty {
                    MochiCard { EmptyMochi(title: "What are we saving for?", message: "A trip, a rainy-day cushion, or something delightfully unnecessary.") }
                } else {
                    ForEach(store.goals) { goal in GoalCard(goal: goal, store: store) { editing = goal } onDelete: { store.deleteGoal(goal) } }
                }
            }.padding(28)
        }
        .sheet(isPresented: $showingAdd) { GoalEditor(store: store) }
        .sheet(item: $editing) { GoalEditor(store: store, editing: $0) }
    }
}

private struct GoalCard: View {
    let goal: SavingsGoal
    @ObservedObject var store: MoneyStore
    let onEdit: () -> Void
    let onDelete: () -> Void
    var ratio: Double { goal.savedAmount / max(goal.targetAmount, 0.01) }
    var body: some View {
        MochiCard {
            HStack(spacing: 22) {
                ZStack {
                    Circle().stroke(.white.opacity(0.10), lineWidth: 10)
                    Circle().trim(from: 0, to: min(ratio, 1)).stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) { Text("\(Int(ratio * 100))%").font(.headline.monospacedDigit()); Text("saved").font(.caption2).foregroundStyle(.secondary) }
                }.frame(width: 98, height: 98)
                VStack(alignment: .leading, spacing: 8) {
                    Text(goal.name).font(.title3.bold())
                    Text("\(store.formatted(goal.savedAmount)) of \(store.formatted(goal.targetAmount))").font(.headline.monospacedDigit())
                    if let date = goal.targetDate { Text("Target · \(date.formatted(date: .long, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                    ProgressView(value: min(ratio, 1)).tint(.white).frame(maxWidth: 450)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    Button("Update", action: onEdit).buttonStyle(.bordered)
                    Menu { Button("Delete goal", role: .destructive, action: onDelete) } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton)
                }
            }
        }
    }
}

private struct GoalEditor: View {
    @ObservedObject var store: MoneyStore
    let editing: SavingsGoal?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var target: Double
    @State private var saved: Double
    @State private var hasDate: Bool
    @State private var date: Date

    init(store: MoneyStore, editing: SavingsGoal? = nil) {
        self.store = store; self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _target = State(initialValue: editing?.targetAmount ?? 1000)
        _saved = State(initialValue: editing?.savedAmount ?? 0)
        _hasDate = State(initialValue: editing?.targetDate != nil)
        _date = State(initialValue: editing?.targetDate ?? Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(editing == nil ? "Plant a new goal" : "Update your goal").font(.title2.bold()); Spacer(); MochiMascot(mood: .proud).scaleEffect(0.55).frame(width: 54, height: 50) }
            Form {
                TextField("Goal name", text: $name, prompt: Text("Japan trip"))
                TextField("Target amount", value: $target, format: .number.precision(.fractionLength(2)))
                TextField("Already saved", value: $saved, format: .number.precision(.fractionLength(2)))
                Toggle("Target date", isOn: $hasDate)
                if hasDate { DatePicker("Date", selection: $date, displayedComponents: .date) }
            }.formStyle(.grouped)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(editing == nil ? "Create goal" : "Save progress") { save() }.monochromeButton()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || target <= 0 || saved < 0)
            }
        }.padding(26).frame(width: 460)
    }

    private func save() {
        if var editing {
            editing.name = name; editing.targetAmount = target; editing.savedAmount = saved; editing.targetDate = hasDate ? date : nil
            store.updateGoal(editing)
        } else { store.addGoal(name: name, target: target, saved: saved, date: hasDate ? date : nil) }
        dismiss()
    }
}
