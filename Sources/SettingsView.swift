import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MoneyStore
    @State private var confirmClear = false
    private let currencies = ["EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD", "PLN"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionTitle("Settings", subtitle: "Your ledger stays on this Mac. Bank sync is optional.")
                MochiCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Money format", systemImage: "eurosign.circle.fill").font(.headline)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) { Text("Currency"); Text("Used throughout the app.").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Picker("Currency", selection: $store.currencyCode) { ForEach(currencies, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 120)
                        }
                    }
                }
                BankSyncSettings(sync: store.bankSync)
                MochiCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Your data", systemImage: "externaldrive.fill").font(.headline)
                        settingsRow(title: "Export transactions", detail: "Save all transactions as a portable CSV file.", button: "Export CSV", symbol: "square.and.arrow.up") { store.exportCSV() }
                        Divider().opacity(0.22)
                        settingsRow(title: "Import transactions", detail: "Add transactions from a Mochi Money CSV export.", button: "Import CSV", symbol: "square.and.arrow.down") { store.importCSV() }
                    }
                }
                MochiCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Playground", systemImage: "sparkles").font(.headline)
                        settingsRow(title: "Try demo data", detail: "Replace current data with a small example month.", button: "Add demo", symbol: "wand.and.stars") { store.addDemoData() }
                        Divider().opacity(0.22)
                        settingsRow(title: "Clear everything", detail: "Delete transactions, budgets, and goals from this Mac.", button: "Clear data", symbol: "trash") { confirmClear = true }
                    }
                }
                MochiCard {
                    HStack(spacing: 20) {
                        MochiMascot().scaleEffect(0.68).frame(width: 70, height: 62)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mochi Money 1.0").font(.headline)
                            Text("Private by default · No analytics · Optional bank connection").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                Text(store.message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
            }.padding(28).frame(maxWidth: 860)
        }
        .alert("Clear all Mochi Money data?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) { }
            Button("Clear everything", role: .destructive) { store.clearAll() }
        } message: { Text("This cannot be undone. Export a CSV first if you need a copy.") }
    }

    private func settingsRow(title: String, detail: String, button: String, symbol: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button(button, systemImage: symbol, action: action).buttonStyle(.bordered)
        }
    }
}
