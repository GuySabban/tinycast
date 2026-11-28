import Foundation

/// The switch under its own raw key (decision D6); the key itself lives only in the Keychain.
@MainActor
@Observable
final class WebSearchSettingsStore {
    enum KeyStatus: Equatable {
        case missing, stored
        /// The Keychain refused to answer, so a key may still be stored (risk R14).
        case unreadable
    }

    private static let enabledKey = "webSearchEnabled"
    private static let account = UUID(uuidString: "6E3B0C3A-2F4D-4B8E-9A51-57E5C0A1D9F2")!
    /// The feature's own scope, so the Platform file's list of scopes stays upstream's.
    static let keychain = KeychainSecretStore(scope: "web-search-keys")

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Cached, so the launcher never reads the Keychain while building rows.
    private(set) var keyStatus: KeyStatus = .missing
    var hasKey: Bool { keyStatus == .stored }

    /// Called after a key is removed, so results fetched with it leave memory too.
    @ObservationIgnored var onKeyRemoved: @MainActor () -> Void = {}
    /// Called after a key is stored, so a failure the old key caused stops showing.
    @ObservationIgnored var onKeyStored: @MainActor () -> Void = {}
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainSecretStore

    init(defaults: UserDefaults = .standard, keychain: KeychainSecretStore = WebSearchSettingsStore.keychain) {
        self.defaults = defaults
        self.keychain = keychain
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        refreshKeyStatus()
    }

    @discardableResult
    func reload() -> Bool {
        let enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        guard isEnabled != enabled else { return false }
        isEnabled = enabled
        return true
    }

    /// A presence check only, so it never shows the Keychain's password prompt.
    func refreshKeyStatus() {
        do {
            keyStatus = try keychain.hasSecret(for: Self.account) ? .stored : .missing
        } catch {
            keyStatus = .unreadable
        }
    }

    /// Reads the secret itself; called on a search, never while building rows.
    func key() throws -> String? {
        try keychain.secret(for: Self.account)
    }

    /// The same read off the main actor, so the Keychain prompt never holds up the launcher.
    func readKey() async throws -> String? {
        try await Self.read(from: keychain, account: Self.account)
    }

    @concurrent
    private nonisolated static func read(from keychain: KeychainSecretStore, account: UUID) async throws -> String? {
        try keychain.secret(for: account)
    }

    /// A blank or nil key removes the stored one.
    func setKey(_ key: String?) throws {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            try keychain.removeSecret(for: Self.account)
            keyStatus = .missing
            onKeyRemoved()
            return
        }
        try keychain.setSecret(trimmed, for: Self.account)
        keyStatus = .stored
        onKeyStored()
    }
}
