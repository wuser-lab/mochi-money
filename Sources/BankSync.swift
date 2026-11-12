#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import AuthenticationServices
#endif
import Combine
import Foundation
import Security

struct ConnectedBank: Codable, Hashable, Identifiable {
    var name: String
    var country: String
    var id: String { country + ":" + name }
}
struct BankSyncPayload: Decodable { var transactions: [BankRecord]; var syncedAt: String }
private struct BankServiceSettings: Codable { var address: String; var token: String; var userID: String? = nil; var appleUserID: String? = nil }
private enum BankServiceKeychain {
    static let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"dev.eldar.mochimoney.banksync", kSecAttrAccount as String:"connection"]
    static func read() -> Data? {
        var request = query; request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
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
    case signInRequired
    var errorDescription: String? { if case .message(let text) = self { return text }; return "Please sign in again to reconnect your banks." }
}

@MainActor
protocol BankLedger: AnyObject {
    var transactions: [MoneyTransaction] { get }
    var currencyCode: String { get }
    func mergeBankRecords(_ records: [BankRecord]) throws -> Int
    func selectBankAccount(_ id: String?) throws
    func removeBankAccount(_ id: String) throws
}
extension BankLedger {
    func selectBankAccount(_ id: String?) throws {}
    func removeBankAccount(_ id: String) throws {}
}

@MainActor
final class BankSync: ObservableObject {
    @Published private(set) var accountID: String?
    @Published private(set) var requiresSignIn = false
    var needsSignIn: Bool { accountID == nil || requiresSignIn }
    @Published var banks: [ConnectedBank] = []
    @Published var connectedBanks: [String] = []
    @Published var busy = false
    @Published var message = "Set up a bank connection service to enable automatic imports."
    @Published private(set) var configured = false
    @Published private(set) var lastSync: Date?
    @Published var automatic: Bool { didSet { UserDefaults.standard.set(automatic,forKey:"bankSyncAutomatic") } }
    @Published var startDate: Date { didSet { UserDefaults.standard.set(startDate,forKey:"bankSyncStartDate") } }
    private weak var store: (any BankLedger)?
    private var settings: BankServiceSettings?
    private var lastAttempt = Date.distantPast
    @Published private(set) var awaitingAuthorization = false
    private var previousAccountCount = 0
    private var previousRevision = ""
    var serviceAddress: String { settings?.address ?? "" }

    init(store: any BankLedger) {
        self.store = store
        automatic = UserDefaults.standard.bool(forKey:"bankSyncAutomatic")
        lastSync = UserDefaults.standard.object(forKey:"bankSyncLastSuccess") as? Date
        let calendar = Calendar.current
        let latestImport = store.transactions.filter { $0.note.hasPrefix("KBC |") || $0.note.hasPrefix("Revolut statement") }.map(\.date).max()
        let firstDay = latestImport.flatMap { calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:$0)) } ?? calendar.startOfDay(for:Date())
        startDate = UserDefaults.standard.object(forKey:"bankSyncStartDate") as? Date ?? min(firstDay,calendar.startOfDay(for:Date()))
        lastAttempt = UserDefaults.standard.object(forKey:"bankSyncLastAttempt") as? Date ?? lastSync ?? .distantPast
        if let data = BankServiceKeychain.read(), let saved = try? JSONDecoder().decode(BankServiceSettings.self,from:data) {
            #if os(iOS)
            if saved.userID != nil && saved.address == Self.hostedAddress {
                settings = saved; accountID = saved.userID; configured = true
                message = "Choose Connect your bank to start syncing."
            }
            #else
            settings = saved; accountID = saved.userID; configured = true; message = "Bank connection service configured."
            #endif
        }
    }
    static var hostedAddress: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MochiAPIBaseURL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    static var savedAccountID: String? {
        guard let data = BankServiceKeychain.read(), let value = try? JSONDecoder().decode(BankServiceSettings.self, from: data), value.address == hostedAddress else { return nil }
        return value.userID
    }
    struct SignInChallenge: Decodable { let challenge: String; let nonce: String }
    private struct SignInSession: Decodable { let token: String; let userID: String }
    func prepareSignIn() async throws -> SignInChallenge {
        guard let address = Self.hostedAddress else { throw BankSyncError.message("Bank connections are not available in this build yet. You can keep using Mochi with manual entries and CSV imports.") }
        return try await Self.send(address: address, path: "auth/challenge", token: nil, body: [:])
    }
    func finishSignIn(challenge: String, identityToken: String, code: String, appleUserID: String? = nil) async throws {
        guard let address = Self.hostedAddress, !busy else { throw BankSyncError.message("Please try signing in again.") }
        busy = true; defer { busy = false }
        let session: SignInSession = try await Self.send(address: address, path: "auth/apple", token: nil,
            body: ["challenge": challenge, "identityToken": identityToken, "authorizationCode": code])
        guard session.userID.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil, session.token.count == 43 else { throw BankSyncError.message("Sign-in returned an invalid session.") }
        try store?.selectBankAccount(session.userID)
        let value = BankServiceSettings(address: address, token: session.token, userID: session.userID, appleUserID: appleUserID)
        do { try BankServiceKeychain.write(JSONEncoder().encode(value)) } catch {
            try? store?.selectBankAccount(accountID)
            throw error
        }
        settings = value; accountID = session.userID; configured = true; requiresSignIn = false
        connectedBanks = []; banks = []; awaitingAuthorization = false
        lastSync = nil; lastAttempt = .distantPast
        // A fresh account starts with history. Existing statement imports retain their date.
        if store?.transactions.isEmpty == true {
            startDate = Calendar.current.date(byAdding: .month, value: -3, to: Calendar.current.dateInterval(of: .month, for: Date())!.start)!
        }
        try await refreshStatus(); try await loadBanks()
        message = "Signed in. Choose your bank to authorize syncing."
    }
    func appleCredentialsRevoked() {
        requiresSignIn = true; automatic = false
        message = "Apple authorization changed. Sign in again before syncing your banks."
    }
    #if os(iOS)
    func checkAppleCredential() async {
        guard let user = settings?.appleUserID else { return }
        let state: ASAuthorizationAppleIDProvider.CredentialState? = await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: user) { state, error in
                continuation.resume(returning: error == nil ? state : nil)
            }
        }
        if state == .revoked || state == .notFound { appleCredentialsRevoked() }
    }
    #endif
    func endAccount(delete: Bool) async throws {
        guard !busy, settings?.userID != nil else { return }
        busy = true; defer { busy = false }
        do {
            let _: Success = try await request(delete ? "account" : "auth/logout", body: [:], method: delete ? "DELETE" : "POST")
        } catch BankSyncError.signInRequired {
            if delete { throw BankSyncError.signInRequired }
        }
        let oldID = accountID
        settings = nil; accountID = nil; requiresSignIn = false; configured = false; automatic = false
        banks = []; connectedBanks = []; lastSync = nil; awaitingAuthorization = false
        BankServiceKeychain.clear()
        try store?.selectBankAccount(nil)
        if delete, let oldID { try store?.removeBankAccount(oldID) }
        message = delete ? "Account deleted and bank access revoked." : "Signed out."
    }
    private static func send<T: Decodable>(address: String, path: String, token: String?, body: [String:Any]?, method: String? = nil) async throws -> T {
        guard let url = URL(string: address + "/" + path) else { throw BankSyncError.message("Connection unavailable.") }
        var request = URLRequest(url: url); request.timeoutInterval = 180
        request.httpMethod = method ?? (body == nil ? "GET" : "POST")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let session = URLSession(configuration: .ephemeral, delegate: NoBankRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw BankSyncError.signInRequired }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String:String])?["error"]
            throw BankSyncError.message(detail ?? "Could not connect to W Money. Try again shortly.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func leaderboard(month: String, country: String?) async throws -> CommunityBoard {
        guard let address = hostedAddress else { throw BankSyncError.message("Worldwide comparisons will be available when W Money’s online service launches.") }
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "month", value: month)]
        if let country, !country.isEmpty { components.queryItems?.append(URLQueryItem(name: "country", value: country)) }
        return try await send(address: address, path: "community/leaderboard?" + (components.percentEncodedQuery ?? ""), token: nil, body: nil)
    }
    func communityProfile() async throws -> CommunityProfile { try await request("community/me") }
    func startCommunityTracking(currency: String) async throws -> CommunityProfile {
        try await request("community/start", body: ["currency": currency])
    }
    func refreshCommunityScore() async throws -> CommunityProfile { try await request("community/refresh", body: [:]) }
    func saveCommunityPrivacy(sharing: Bool, country: String?) async throws -> CommunityProfile {
        try await request("community/privacy", body: ["sharing": sharing, "country": country ?? ""])
    }
    func stopCommunityTracking() async throws -> CommunityProfile { try await request("community/tracking", body: [:], method: "DELETE") }
    @discardableResult
    func configure(address: String, token: String) async -> Bool {
        guard !busy else {return false}; busy = true; defer {busy = false}
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
            return true
        } catch {message = error.localizedDescription; return false}
    }
    private struct Status: Decodable {var connectedBanks:[String]; var accountCount:Int; var revision:String?}
    private struct BankList: Decodable {var banks:[ConnectedBank]}
    private struct AuthLink: Decodable {var url:String}
    private struct Success: Decodable {var ok:Bool}
    private func request<T: Decodable>(_ path: String, body: [String:Any]? = nil, method: String? = nil) async throws -> T {
        guard let settings else { throw BankSyncError.message("Sign in to connect your bank.") }
        do { return try await Self.send(address: settings.address, path: path, token: settings.token, body: body, method: method) }
        catch BankSyncError.signInRequired { requiresSignIn = true; throw BankSyncError.signInRequired }
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
    @discardableResult
    func connect(_ bank: ConnectedBank) async -> Bool {
        guard !busy else {return false}; busy = true; defer {busy = false}
        do {
            let result: AuthLink = try await request("connect",body:["name":bank.name,"country":bank.country])
            guard let url = URL(string:result.url), url.scheme == "https" else {throw BankSyncError.message("The provider returned an invalid bank login link.")}
            awaitingAuthorization = true
            #if os(macOS)
            let opened = NSWorkspace.shared.open(url)
            #elseif os(iOS)
            let opened = await UIApplication.shared.open(url)
            #endif
            guard opened else {throw BankSyncError.message("Could not open your browser.")}
            automatic = true; message = "Approve access in your bank's browser flow, then return here."
            return true
        } catch {awaitingAuthorization = false; message = error.localizedDescription; return false}
    }
    func sync() async {
        guard configured && !busy else {return}; busy = true; lastAttempt = Date(); UserDefaults.standard.set(lastAttempt,forKey:"bankSyncLastAttempt"); defer {busy = false}
        do {
            try await refreshStatus()
            guard !awaitingAuthorization else { message = "Waiting for bank approval. Finish the approval page, then try again."; return }
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
            if configured && !busy && !requiresSignIn {
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

struct CommunityScore: Decodable {
    let month: String
    let improvement: Double
    let updatedAt: String
}
struct CommunityProfile: Decodable {
    let tracking: Bool
    let sharing: Bool
    let nickname: String
    let country: String?
    let eligibleMonth: String?
    let baselineRate: Double?
    let score: CommunityScore?
}
struct CommunityEntry: Decodable {
    let rank: Int
    let nickname: String
    let country: String?
    let improvement: Double
    let month: String
    let updatedAt: String
}
struct CommunityBoard: Decodable {
    let month: String
    let entries: [CommunityEntry]
}
