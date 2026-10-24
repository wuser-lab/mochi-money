import AppKit
import Combine
import Foundation
import Security

struct ConnectedBank: Codable, Hashable, Identifiable {
    var name: String
    var country: String
    var id: String { country + ":" + name }
}
struct BankSyncPayload: Decodable { var transactions: [BankRecord]; var syncedAt: String }
private struct BankServiceSettings: Codable { var address: String; var token: String }
private enum BankServiceKeychain {
    static let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"dev.eldar.mochimoney.banksync", kSecAttrAccount as String:"connection"]
    static func read() -> Data? {
        var request = query; request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    static func write(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary,nil) == errSecSuccess else { throw BankSyncError.message("Could not save the connection key in Keychain.") }
        } else if status != errSecSuccess { throw BankSyncError.message("Could not update the connection key in Keychain.") }
    }
}
enum BankSyncError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor
final class BankSync: ObservableObject {
    @Published var banks: [ConnectedBank] = []
    @Published var connectedBanks: [String] = []
    @Published var busy = false
    @Published var message = "Set up a bank connection service to enable automatic imports."
    @Published private(set) var configured = false
    @Published private(set) var lastSync: Date?
    @Published var automatic: Bool { didSet { UserDefaults.standard.set(automatic,forKey:"bankSyncAutomatic") } }
    @Published var startDate: Date { didSet { UserDefaults.standard.set(startDate,forKey:"bankSyncStartDate") } }
    private weak var store: MoneyStore?
    private var settings: BankServiceSettings?
    private var lastAttempt = Date.distantPast
    private var awaitingAuthorization = false
    private var previousAccountCount = 0
    private var previousRevision = ""
    var serviceAddress: String { settings?.address ?? "" }

    init(store: MoneyStore) {
        self.store = store
        automatic = UserDefaults.standard.bool(forKey:"bankSyncAutomatic")
        lastSync = UserDefaults.standard.object(forKey:"bankSyncLastSuccess") as? Date
        let calendar = Calendar.current
        let latestImport = store.transactions.filter { $0.note.hasPrefix("KBC |") || $0.note.hasPrefix("Revolut statement") }.map(\.date).max()
        let firstDay = latestImport.flatMap { calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:$0)) } ?? calendar.startOfDay(for:Date())
        startDate = UserDefaults.standard.object(forKey:"bankSyncStartDate") as? Date ?? min(firstDay,calendar.startOfDay(for:Date()))
        lastAttempt = UserDefaults.standard.object(forKey:"bankSyncLastAttempt") as? Date ?? lastSync ?? .distantPast
        if let data = BankServiceKeychain.read(), let saved = try? JSONDecoder().decode(BankServiceSettings.self,from:data) {
            settings = saved; configured = true; message = "Bank connection service configured."
        }
    }
    func configure(address: String, token: String) async {
        guard !busy else {return}; busy = true; defer {busy = false}
        do {
            guard let url = URL(string:address.trimmingCharacters(in:.whitespacesAndNewlines)),
                  let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path.isEmpty || url.path == "/",
                  url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1","localhost"].contains(host)), token.count >= 32 else {
                throw BankSyncError.message("Enter an HTTPS service address (or localhost) and its connection key.")
            }
            let candidate = BankServiceSettings(address:address.trimmingCharacters(in:CharacterSet(charactersIn:"/ ").union(.newlines)),token:token)
            let old = settings; settings = candidate
            do {
                let _: Status = try await request("status")
                try BankServiceKeychain.write(JSONEncoder().encode(candidate))
            } catch {settings = old; throw error}
            configured = true; try await refreshStatus(); try await loadBanks()
            message = "Choose your bank, then approve read-only access in your browser."
        } catch {message = error.localizedDescription}
    }
    private struct Status: Decodable {var connectedBanks:[String]; var accountCount:Int; var revision:String?}
    private struct BankList: Decodable {var banks:[ConnectedBank]}
    private struct AuthLink: Decodable {var url:String}
    private struct Success: Decodable {var ok:Bool}
    private func request<T: Decodable>(_ path: String, body: [String:String]? = nil) async throws -> T {
        guard let settings, let url = URL(string:settings.address + "/" + path) else {throw BankSyncError.message("Set up the bank connection service first.")}
        var request = URLRequest(url:url); request.timeoutInterval = 180
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("Bearer " + settings.token,forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if let body {request.httpBody = try JSONEncoder().encode(body)}
        // Never forward the service credential to an HTTP redirect destination.
        let session = URLSession(configuration:.ephemeral,delegate:NoBankRedirects(),delegateQueue:nil)
        defer {session.finishTasksAndInvalidate()}
        let (data,response) = try await session.data(for:request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            let detail = (try? JSONSerialization.jsonObject(with:data) as? [String:String])?["error"]
            throw BankSyncError.message(detail ?? "Could not reach the bank connection service.")
        }
        return try JSONDecoder().decode(T.self,from:data)
    }
    private func refreshStatus() async throws {
        let status: Status = try await request("status"); connectedBanks = status.connectedBanks
        if awaitingAuthorization && (status.accountCount > previousAccountCount || (status.revision ?? "") != previousRevision) {awaitingAuthorization = false; lastAttempt = .distantPast}
        previousAccountCount = status.accountCount; previousRevision = status.revision ?? ""
    }
    private func loadBanks() async throws {let response: BankList = try await request("banks"); banks = response.banks.sorted {$0.name < $1.name}}
    func refresh() async {
        guard configured && !busy else {return}; busy = true; defer {busy = false}
        do {try await refreshStatus(); try await loadBanks()} catch {message = error.localizedDescription}
    }
    func connect(_ bank: ConnectedBank) async {
        guard !busy else {return}; busy = true; defer {busy = false}
        do {
            let result: AuthLink = try await request("connect",body:["name":bank.name,"country":bank.country])
            guard let url = URL(string:result.url), url.scheme == "https" else {throw BankSyncError.message("The provider returned an invalid bank login link.")}
            guard NSWorkspace.shared.open(url) else {throw BankSyncError.message("Could not open your browser.")}
            awaitingAuthorization = true; automatic = true; message = "Approve access in your bank's browser flow, then return here."
        } catch {message = error.localizedDescription}
    }
    func sync() async {
        guard configured && !busy else {return}; busy = true; lastAttempt = Date(); UserDefaults.standard.set(lastAttempt,forKey:"bankSyncLastAttempt"); defer {busy = false}
        do {
            try await refreshStatus()
            guard !connectedBanks.isEmpty else {message = "Connect a bank to start importing payments."; return}
            let formatter = DateFormatter(); formatter.calendar = Calendar(identifier:.gregorian); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            let result: BankSyncPayload = try await request("sync",body:["dateFrom":formatter.string(from:startDate)])
            guard let store else {return}
            let count = try store.mergeBankRecords(result.transactions)
            lastSync = Date(); UserDefaults.standard.set(lastSync,forKey:"bankSyncLastSuccess")
            message = count == 0 ? "Up to date. No new payments." : "Imported \(count) new payment\(count == 1 ? "" : "s")."
        } catch {message = error.localizedDescription}
    }
    func disconnect() async {
        guard configured && !busy else {return}; busy = true; defer {busy = false}
        do {
            let _: Success = try await request("disconnect",body:[:])
            connectedBanks = []; previousAccountCount = 0; awaitingAuthorization = false; automatic = false
            message = "Bank access revoked. Imported transactions are kept."
        } catch {message = error.localizedDescription}
    }
    func run() async {
        while !Task.isCancelled {
            if configured && !busy {
                if awaitingAuthorization {
                    do {try await refreshStatus()} catch {message = error.localizedDescription}
                }
                if automatic && !awaitingAuthorization && Date().timeIntervalSince(lastAttempt) >= 6*3600 {await sync()}
            }
            do {try await Task.sleep(for:.seconds(30))} catch {break}
        }
    }
}
private final class NoBankRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {completionHandler(nil)}
}
