import Foundation
import Combine

@MainActor final class PhoneLedger: ObservableObject, BankLedger, Identifiable {
    lazy var bankSync = BankSync(store: self)
    var transactions: [MoneyTransaction] { data.transactions }
    var currencyCode: String { data.currencyCode }
    func mergeBankRecords(_ records: [BankRecord]) throws -> Int {
        guard !loadFailed else { throw BankSyncError.message("Saved ledger could not be loaded. Restart before syncing.") }
        let result = try BankMerge.merge(records, into: data.transactions, currency: data.currencyCode)
        var next = data; next.transactions = result.items
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(next).write(to: url, options: [.atomic, .completeFileProtection])
        data = next
        return result.added
    }
    @Published var data = StoredData()
    @Published var error: String?
    @Published private(set) var loadFailed = false
    var canChangeCurrency: Bool { data.transactions.isEmpty && data.goals.isEmpty && data.budgets.isEmpty }
    private var url: URL
    private let folder: URL
    private static func ledgerURL(_ id: String?, folder: URL) -> URL {
        folder.appendingPathComponent(id.map { "account-" + $0 + ".json" } ?? "money.json")
    }
    func selectBankAccount(_ id: String?) throws {
        guard id == nil || id!.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw BankSyncError.message("Invalid account.") }
        let target = Self.ledgerURL(id, folder: folder)
        data = StoredData(); url = target; loadFailed = false
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            data = try decoder.decode(StoredData.self, from: Data(contentsOf: target))
        } catch { loadFailed = true; throw error }
    }
    func removeBankAccount(_ id: String) throws {
        guard id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return }
        let file = Self.ledgerURL(id, folder: folder)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    init(storageURL: URL? = nil) {
        folder = storageURL?.deletingLastPathComponent() ?? URL.documentsDirectory
        url = storageURL ?? Self.ledgerURL(BankSync.savedAccountID, folder: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            data = try decoder.decode(StoredData.self, from: Data(contentsOf: url))
        } catch { loadFailed = true; self.error = "Could not read saved ledger. Restart before editing to avoid overwriting it: \(error.localizedDescription)" }
    }
    @discardableResult func update(_ change: (inout StoredData) -> Void) -> Bool {
        var next = data
        change(&next)
        do {
            try persist(next)
            data = next
            return true
        } catch { self.error = "Save failed: \(error.localizedDescription)"; return false }
    }
    private func persist(_ next: StoredData) throws {
        guard !loadFailed else { throw BankSyncError.message("Saved ledger could not be loaded. Restart before editing.") }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(next).write(to: url, options: [.atomic, .completeFileProtection])
    }
    @discardableResult func save() -> Bool { update { _ in } }
    @discardableResult func importCSV(_ text: String) throws -> Int {
        let records = try CSVCodec.decode(text)
        var ids = Set(data.transactions.compactMap(\.bankID))
        let added = records.filter { $0.bankID.map { ids.insert($0).inserted } ?? true }
        var next = data
        next.transactions = ImportRules.apply(to: data.transactions + added)
        try persist(next)
        data = next
        return added.count
    }
    func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try importCSV(String(contentsOf: url, encoding: .utf8))
        } catch { self.error = "Import failed: \(error.localizedDescription)" }
    }
}
