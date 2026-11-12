import Foundation

@main struct PhoneLedgerTests {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.json")
        let ledger = PhoneLedger(storageURL: url)
        let record = BankRecord(bankID: "one", accountID: "account", currency: "EUR", title: "Groceries", amount: 30, kind: .expense, date: "2026-10-20T12:00:00Z", note: "", isInternalTransfer: false)
        let first = try ledger.mergeBankRecords([record])
        precondition(first == 1)
        let reload = PhoneLedger(storageURL: url)
        precondition(reload.transactions.count == 1)
        let second = try ledger.mergeBankRecords([record])
        precondition(second == 0 && ledger.transactions.count == 1)
        let saved = try Data(contentsOf: url)
        var foreign = record; foreign.currency = "USD"; foreign.bankID = "two"
        do {
            _ = try ledger.mergeBankRecords([record, foreign])
            preconditionFailure("Mixed currency accepted")
        } catch { }
        precondition(ledger.transactions.count == 1)
        let afterFailure = try Data(contentsOf: url)
        precondition(afterFailure == saved)
        let badURL = folder.appendingPathComponent("missing/ledger.json")
        let failing = PhoneLedger(storageURL: badURL)
        do {
            _ = try failing.mergeBankRecords([record])
            preconditionFailure("Write failure ignored")
        } catch { }
        precondition(failing.transactions.isEmpty)
        let original = failing.data
        precondition(!failing.update { $0.goals.append(SavingsGoal(name: "Trip", targetAmount: 500, savedAmount: 20)) })
        precondition(failing.data.goals == original.goals, "a failed write must not appear saved in memory")
        let statement = CSVCodec.encode(ledger.transactions)
        do {
            _ = try failing.importCSV(statement)
            preconditionFailure("Failed CSV write ignored")
        } catch { }
        precondition(failing.transactions.isEmpty, "failed imports must leave the ledger unchanged")
        let imported = PhoneLedger(storageURL: folder.appendingPathComponent("import.json"))
        let count = try imported.importCSV(statement)
        precondition(count == 1 && imported.transactions.count == 1)
        let repeated = try imported.importCSV(statement)
        precondition(repeated == 0 && imported.transactions.count == 1, "bank IDs prevent duplicate CSV imports")
        try Data("broken".utf8).write(to: url)
        let broken = PhoneLedger(storageURL: url)
        precondition(broken.loadFailed)
        do {
            _ = try broken.importCSV(statement)
            preconditionFailure("CSV overwrote an unreadable ledger")
        } catch { }
        precondition(broken.transactions.isEmpty)
        do {
            _ = try broken.mergeBankRecords([record])
            preconditionFailure("Unreadable ledger overwritten")
        } catch { }
        let stillBroken = try Data(contentsOf: url)
        precondition(stillBroken == Data("broken".utf8))
        let alice = String(repeating: "a", count: 64), bob = String(repeating: "b", count: 64)
        try reload.selectBankAccount(alice)
        precondition(reload.transactions.isEmpty)
        _ = try reload.mergeBankRecords([record])
        try reload.selectBankAccount(bob)
        precondition(reload.transactions.isEmpty, "another account must never inherit the ledger")
        try reload.selectBankAccount(alice)
        precondition(reload.transactions.count == 1)
        try reload.selectBankAccount(nil)
        precondition(reload.transactions.isEmpty, "sign-out must detach private account data")
        try reload.removeBankAccount(alice)
        try reload.selectBankAccount(alice)
        precondition(reload.transactions.isEmpty, "deleted account ledger is removed")
        print("Phone ledger persistence and atomic bank import tests passed")
    }
}
