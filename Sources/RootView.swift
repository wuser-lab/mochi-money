import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Overview"
    case transactions = "Transactions"
    case budgets = "Budgets"
    case goals = "Goals"
    case settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .transactions: return "list.bullet.rectangle.fill"
        case .budgets: return "chart.bar.fill"
        case .goals: return "flag.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct RootView: View {
    @ObservedObject var store: MoneyStore
    @State private var selection: AppSection? = .dashboard
    @State private var showingAdd = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                brand
                List(AppSection.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .tag(section)
                        .padding(.vertical, 4)
                }
                .listStyle(.sidebar)
                Button { showingAdd = true } label: {
                    Label("Add transaction", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .monochromeButton()
                .padding(16)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard: DashboardView(store: store, showingAdd: $showingAdd)
                case .transactions: TransactionsView(store: store, showingAdd: $showingAdd)
                case .budgets: BudgetsView(store: store)
                case .goals: GoalsView(store: store)
                case .settings: SettingsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1040, minHeight: 690)
        .sheet(isPresented: $showingAdd) { TransactionEditor(store: store) }
        .onReceive(NotificationCenter.default.publisher(for: .newTransaction)) { _ in showingAdd = true }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            MochiMascot().scaleEffect(0.52).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mochi Money").font(.system(size: 18, weight: .bold, design: .rounded))
                Text("soft money tracking").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
