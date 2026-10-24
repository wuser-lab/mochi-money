import SwiftUI

@main
struct MochiMoneyApp: App {
    @StateObject private var store = MoneyStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .task { await store.bankSync.run() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Transaction") {
                    NotificationCenter.default.post(name: .newTransaction, object: nil)
                }.keyboardShortcut("n")
            }
        }
    }
}

extension Notification.Name {
    static let newTransaction = Notification.Name("MochiMoney.newTransaction")
}
