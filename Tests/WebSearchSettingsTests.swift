import Foundation
import Synchronization

/// The settings store over a real Keychain scope of its own, feeding a real session and provider.
@main
@MainActor
struct WebSearchSettingsTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        if (try? condition()) == true {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expectSettles(_ message: String, within seconds: Double = 5, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition() {
            guard ContinuousClock.now < deadline else { return expect(false, message) }
            try? await Task.sleep(for: .milliseconds(5))
        }
        expect(true, message)
    }

    static func main() async throws {
        startsOnWithNoKey()
        keepsTheSwitch()
        storesAKeyOnlyInTheKeychain()
        aBlankKeyRemovesTheStoredOne()
        replacingAKeyKeepsResults()
        await searchesWithTheStoredKey()
        await removingTheKeyForgetsResults()
        await removingTheKeyStopsASearch()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - World

    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appending(path: "web-search-fixtures")
    static let lite = (try? Data(contentsOf: fixtures.appending(path: "search-lite.json"))) ?? Data()

    struct World {
        let suite: String
        let defaults: UserDefaults
        let keychain: KeychainSecretStore
        let settings: WebSearchSettingsStore
    }

    /// A fresh defaults suite and Keychain scope per case, removed again when the case ends.
    static func world(_ name: String, body: @MainActor (World) async -> Void) async {
        let suite = "WebSearchSettingsTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainSecretStore(scope: "web-search-test-" + UUID().uuidString, bundleIdentifier: "test.tinycast")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? WebSearchSettingsStore(defaults: defaults, keychain: keychain).setKey(nil)
        }
        await body(World(
            suite: suite, defaults: defaults, keychain: keychain,
            settings: .init(defaults: defaults, keychain: keychain)))
    }

    static func syncWorld(_ name: String, body: (World) throws -> Void) {
        let suite = "WebSearchSettingsTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainSecretStore(scope: "web-search-test-" + UUID().uuidString, bundleIdentifier: "test.tinycast")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? WebSearchSettingsStore(defaults: defaults, keychain: keychain).setKey(nil)
        }
        do {
            try body(World(
                suite: suite, defaults: defaults, keychain: keychain,
                settings: .init(defaults: defaults, keychain: keychain)))
        } catch {
            expect(false, "\(name) threw \(error)")
        }
    }

    /// The launcher's wiring: a provider made from the stored key on each search.
    static func session(over settings: WebSearchSettingsStore) -> WebSearchSession {
        let session = WebSearchSession(limit: 5) {
            guard let key = try? settings.key() else { return nil }
            return ExaSearchProvider(
                key: key, baseURL: URL(string: "https://exa.test/")!, protocolClasses: [ExaFixture.self])
        }
        settings.onKeyRemoved = { [weak session] in session?.forget() }
        return session
    }

    static func settled(_ session: WebSearchSession) async {
        await expectSettles("the search settles") {
            if case .searching = session.state { return false }
            return true
        }
    }

    // MARK: - Cases

    static func startsOnWithNoKey() {
        syncWorld("fresh") { world in
            expect(world.settings.isEnabled, "the switch starts on")
            expect(world.settings.keyStatus == .missing, "no key is stored at first")
            expect(!world.settings.hasKey, "and hasKey says so")
            expect(try world.settings.key() == nil, "reading the key finds nothing")
        }
    }

    static func keepsTheSwitch() {
        syncWorld("switch") { world in
            world.settings.isEnabled = false
            let reopened = WebSearchSettingsStore(defaults: world.defaults, keychain: world.keychain)
            expect(!reopened.isEnabled, "the switch survives a relaunch")
            expect(world.defaults.object(forKey: "webSearchEnabled") as? Bool == false, "under its own raw key")
        }
    }

    static func storesAKeyOnlyInTheKeychain() {
        syncWorld("store") { world in
            try world.settings.setKey("  exa-key-123 \n")
            expect(world.settings.keyStatus == .stored, "a saved key reads as stored")
            expect(try world.settings.key() == "exa-key-123", "the key is stored trimmed")
            let reopened = WebSearchSettingsStore(defaults: world.defaults, keychain: world.keychain)
            expect(reopened.hasKey, "a relaunch finds the key without reading it")
            let written = world.defaults.persistentDomain(forName: world.suite) ?? [:]
            expect(
                !written.values.contains { "\($0)".contains("exa-key-123") },
                "the key is never written to defaults")
        }
    }

    static func aBlankKeyRemovesTheStoredOne() {
        syncWorld("blank") { world in
            var removals = 0
            world.settings.onKeyRemoved = { removals += 1 }
            try world.settings.setKey("exa-key-123")
            try world.settings.setKey("   ")
            expect(world.settings.keyStatus == .missing, "a blank key removes the stored one")
            expect(try world.settings.key() == nil, "and the Keychain holds nothing")
            try world.settings.setKey("exa-key-123")
            try world.settings.setKey(nil)
            expect(try world.settings.key() == nil, "nil removes it too")
            expect(removals == 2, "each removal is announced")
            try world.settings.setKey(nil)
            expect(world.settings.keyStatus == .missing, "removing no key is harmless")
        }
    }

    static func replacingAKeyKeepsResults() {
        syncWorld("replace") { world in
            var removals = 0
            world.settings.onKeyRemoved = { removals += 1 }
            try world.settings.setKey("first")
            try world.settings.setKey("second")
            expect(try world.settings.key() == "second", "a new key replaces the old one")
            expect(removals == 0, "a replacement is not a removal")
        }
    }

    static func searchesWithTheStoredKey() async {
        await world("search") { world in
            ExaFixture.reset(.serve(200, lite))
            let session = session(over: world.settings)
            session.search("swift")
            expect(session.state == .failed(query: "swift", .missingKey), "no stored key sends nothing")
            expect(ExaFixture.requests.isEmpty, "not one request")
            try? world.settings.setKey("exa-key-123")
            session.search("swift")
            await settled(session)
            expect(ExaFixture.requests.map(\.key) == ["exa-key-123"], "the stored key goes with the search")
            expect(session.results(for: "swift")?.count == 5, "and its results are kept")
        }
    }

    static func removingTheKeyForgetsResults() async {
        await world("forget") { world in
            ExaFixture.reset(.serve(200, lite))
            try? world.settings.setKey("exa-key-123")
            let session = session(over: world.settings)
            session.search("swift")
            await settled(session)
            session.search("swiftui")
            await settled(session)
            expect(session.results.count == 2, "two queries are remembered")
            try? world.settings.setKey(nil)
            expect(session.results.isEmpty, "removing the key forgets every remembered query")
            expect(session.results(for: "swift") == nil, "so nothing is shown from memory")
            try? world.settings.setKey("exa-key-456")
            session.search("swift")
            expect(session.state == .searching(query: "swift"), "the next search asks Exa again")
            await settled(session)
            expect(ExaFixture.requests.last?.key == "exa-key-456", "with the new key")
            expect(ExaFixture.requests.count == 3, "one request per search, none from memory")
        }
    }

    static func removingTheKeyStopsASearch() async {
        await world("inflight") { world in
            ExaFixture.reset(.hold)
            try? world.settings.setKey("exa-key-123")
            let session = session(over: world.settings)
            session.search("swift")
            await expectSettles("the request is in flight") { ExaFixture.requests.count == 1 }
            try? world.settings.setKey(nil)
            expect(session.state == .idle, "removing the key stops the search")
            await expectSettles("the request is stopped") { ExaFixture.stopped == 1 }
            ExaFixture.release(lite)
            try? await Task.sleep(for: .milliseconds(100))
            expect(session.results(for: "swift") == nil, "a reply fetched with the old key is dropped")
        }
    }
}

final class ExaFixture: URLProtocol, @unchecked Sendable {
    enum Mode {
        case serve(Int, Data)
        /// Answers nothing until `release`, so a case can act while the request is in flight.
        case hold
    }

    struct Seen {
        let key: String?
    }

    private struct State {
        var mode: Mode = .hold
        var requests: [Seen] = []
        var held: [ExaFixture] = []
        var answered: Set<ObjectIdentifier> = []
        var halted: Set<ObjectIdentifier> = []
        var stopped = 0
    }

    private static let state = Mutex(State())

    static var requests: [Seen] { state.withLock { $0.requests } }
    static var stopped: Int { state.withLock { $0.stopped } }
    static func reset(_ mode: Mode) { state.withLock { $0 = State(mode: mode) } }

    static func release(_ data: Data) {
        let (held, halted) = state.withLock { state in
            defer { state.held = [] }
            return (state.held, state.halted)
        }
        for fixture in held where !halted.contains(ObjectIdentifier(fixture)) { fixture.reply(status: 200, data) }
    }

    override static func canInit(with request: URLRequest) -> Bool { request.url?.host == "exa.test" }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let seen = Seen(key: request.value(forHTTPHeaderField: "x-api-key"))
        let mode = Self.state.withLock { state in
            state.requests.append(seen)
            if case .hold = state.mode { state.held.append(self) }
            return state.mode
        }
        if case .serve(let status, let data) = mode { reply(status: status, data) }
    }

    override func stopLoading() {
        let me = ObjectIdentifier(self)
        Self.state.withLock { state in
            state.halted.insert(me)
            if !state.answered.contains(me) { state.stopped += 1 }
        }
    }

    private func reply(status: Int, _ data: Data) {
        Self.state.withLock { _ = $0.answered.insert(ObjectIdentifier(self)) }
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
