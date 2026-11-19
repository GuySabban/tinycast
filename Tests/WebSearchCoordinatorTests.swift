import Foundation
import Synchronization

/// The coordinator over a real settings store, Keychain scope, session and provider, with Exa faked.
@main
@MainActor
struct WebSearchCoordinatorTests {
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
        await typingNeverSearches()
        await searchingShowsPlaceholdersThenResults()
        await rowsBelongToTheirQuery()
        await knownQueriesComeFromMemory()
        await aMissingKeyPointsAtSettings()
        await aRejectedKeyPointsAtSettings()
        await aFailureRetries()
        await openingAResultOpensItsLink()
        await onlyWebLinksOpen()
        await copyingALink()
        await switchingOffStopsTheSearch()
        await removingTheKeyForgetsResults()
        await removingTheKeyStopsASearch()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appending(path: "web-search-fixtures")
    static func fixture(_ name: String) -> Data {
        (try? Data(contentsOf: fixtures.appending(path: name))) ?? Data()
    }
    static let lite = fixture("search-lite.json")

    struct World {
        let settings: WebSearchSettingsStore
        let session: WebSearchSession
        let coordinator: WebSearchCoordinator
        let core: AppCore
        let palette: PaletteCoordinator
        let settingsWindow: SettingsCoordinator
        let opened: Box<[URL]>
        let copied: Box<[String]>
    }

    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    /// AppCore's own wiring, against a fresh defaults suite and Keychain scope removed when the case ends.
    static func world(_ name: String, key: String? = "exa-key-123", body: @MainActor (World) async -> Void) async {
        let suite = "WebSearchCoordinatorTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainSecretStore(
            scope: "web-search-test-" + UUID().uuidString, bundleIdentifier: "test.tinycast")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? WebSearchSettingsStore(defaults: defaults, keychain: keychain).setKey(nil)
        }
        let settings = WebSearchSettingsStore(defaults: defaults, keychain: keychain)
        do { try settings.setKey(key) } catch { return expect(false, "\(name) could not store the key: \(error)") }
        let session = WebSearchSession(
            limit: WebSearchCoordinator.resultLimit,
            provider: WebSearchCoordinator.provider(
                for: settings, baseURL: URL(string: "https://exa.test/")!, protocolClasses: [ExaFixture.self]))
        let core = AppCore()
        let palette = PaletteCoordinator()
        let settingsWindow = SettingsCoordinator()
        let opened = Box<[URL]>([])
        let copied = Box<[String]>([])
        let coordinator = WebSearchCoordinator(
            settings: settings, session: session, paletteCoordinator: palette,
            settingsCoordinator: settingsWindow, core: core,
            openURL: { opened.value.append($0) },
            copyText: { copied.value.append($0); return true })
        await body(World(
            settings: settings, session: session, coordinator: coordinator, core: core, palette: palette,
            settingsWindow: settingsWindow, opened: opened, copied: copied))
    }

    static func settled(_ session: WebSearchSession, line: Int = #line) async {
        await expectSettles("the search settles (line \(line))") {
            if case .searching = session.state { return false }
            return true
        }
    }

    static func results(_ rows: [WebSearchRow]) -> [WebSearchResult] {
        rows.compactMap { if case .result(let result) = $0 { result } else { nil } }
    }

    // MARK: - Cases

    static func typingNeverSearches() async {
        ExaFixture.reset(.serve(200, lite))
        await world("typing") { w in
            expect(w.coordinator.isAvailable, "on with a key is available")
            for prefix in ["s", "sw", "swift", "swift concurrency"] {
                expect(w.coordinator.launcherRows(for: prefix).isEmpty, "no rows for '\(prefix)' before Return")
            }
            expect(ExaFixture.requests.isEmpty, "reading rows sends nothing")
            expect(w.coordinator.launcherRows(for: "   ").isEmpty, "a blank query has no rows")
        }
    }

    static func searchingShowsPlaceholdersThenResults() async {
        ExaFixture.reset(.hold)
        await world("placeholders") { w in
            w.coordinator.search("swift concurrency")
            expect(
                w.coordinator.launcherRows(for: "swift concurrency")
                    == WebSearchRow.placeholders(count: WebSearchCoordinator.resultLimit),
                "five placeholders the moment Return is pressed")
            expect(w.palette.hidden == 0, "the panel stays open for the results")
            await expectSettles("the request is in flight") { ExaFixture.requests.count == 1 }
            ExaFixture.release(lite)
            await settled(w.session)
            let rows = w.coordinator.launcherRows(for: " swift concurrency ")
            expect(results(rows).count == rows.count && !rows.isEmpty, "only result rows once answered")
            expect(rows.count <= WebSearchCoordinator.resultLimit, "never more than five")
            expect(ExaFixture.requests.map(\.key) == ["exa-key-123"], "the stored key goes with the search")
        }
    }

    static func rowsBelongToTheirQuery() async {
        ExaFixture.reset(.hold)
        await world("other-query") { w in
            w.coordinator.search("swift")
            expect(w.coordinator.launcherRows(for: "swift ui").isEmpty, "a changed query shows no placeholders")
            await expectSettles("the request is in flight") { ExaFixture.requests.count == 1 }
            ExaFixture.release(lite)
            await settled(w.session)
            expect(w.coordinator.launcherRows(for: "swift ui").isEmpty, "nor another query's results")
            expect(!w.coordinator.launcherRows(for: "swift").isEmpty, "back to the query, back to its results")
        }
    }

    static func knownQueriesComeFromMemory() async {
        ExaFixture.reset(.serve(200, lite))
        await world("memory") { w in
            w.coordinator.search("swift")
            await settled(w.session)
            w.coordinator.search("swift")
            await settled(w.session)
            expect(ExaFixture.requests.count == 1, "Return on a known query sends nothing")
            w.coordinator.searchAgain("swift")
            await settled(w.session)
            expect(ExaFixture.requests.count == 2, "Search Again always asks")
            expect(!w.coordinator.launcherRows(for: "swift").isEmpty, "and keeps showing results")
        }
    }

    static func aMissingKeyPointsAtSettings() async {
        ExaFixture.reset(.serve(200, lite))
        await world("missing-key", key: nil) { w in
            expect(!w.coordinator.isAvailable, "no key is not available")
            w.coordinator.search("swift")
            let rows = w.coordinator.launcherRows(for: "swift")
            expect(rows == [.failure(.missingKey)], "one failure row")
            w.coordinator.open(rows[0])
            expect(w.settingsWindow.shown == [.fallbacks], "Return opens the Fallbacks pane")
            expect(w.palette.hidden == 1, "and puts the panel away")
            expect(ExaFixture.requests.isEmpty, "nothing was sent")
        }
    }

    static func aRejectedKeyPointsAtSettings() async {
        ExaFixture.reset(.serve(401, fixture("error-401.json")))
        await world("rejected-key") { w in
            w.coordinator.search("swift")
            await settled(w.session)
            let rows = w.coordinator.launcherRows(for: "swift")
            expect(rows == [.failure(.unauthorized)], "a 401 is one failure row")
            w.coordinator.open(rows[0])
            expect(w.settingsWindow.shown == [.fallbacks], "Return opens the Fallbacks pane")
            expect(ExaFixture.requests.count == 1, "not a retry with the same key")
        }
    }

    static func aFailureRetries() async {
        ExaFixture.reset(.serve(500, Data()))
        await world("retry") { w in
            w.coordinator.search("swift")
            await settled(w.session)
            let rows = w.coordinator.launcherRows(for: "swift")
            expect(rows == [.failure(.server)], "a 500 is one failure row")
            ExaFixture.reset(.serve(200, lite))
            w.coordinator.open(rows[0])
            await settled(w.session)
            expect(ExaFixture.requests.count == 1, "Return on the failure asks again")
            expect(!results(w.coordinator.launcherRows(for: "swift")).isEmpty, "and the results replace it")
            expect(w.settingsWindow.shown.isEmpty && w.palette.hidden == 0, "without leaving the panel")
        }
    }

    static func openingAResultOpensItsLink() async {
        ExaFixture.reset(.serve(200, lite))
        await world("open") { w in
            w.coordinator.search("swift")
            await settled(w.session)
            guard let first = w.coordinator.launcherRows(for: "swift").first, case .result(let result) = first else {
                return expect(false, "a result to open")
            }
            w.coordinator.open(.placeholder(0))
            expect(w.opened.value.isEmpty, "a placeholder opens nothing")
            w.coordinator.open(first)
            expect(w.opened.value == [result.url], "Return opens the result's link")
            expect(w.palette.hidden == 1, "and puts the panel away")
        }
    }

    static func onlyWebLinksOpen() async {
        await world("web-links") { w in
            for link in ["file:///etc/passwd", "javascript:alert(1)", "https://user:pw@example.com/"] {
                let result = WebSearchResult(
                    title: "t", url: URL(string: link)!, snippet: "", host: "example.com", published: nil)
                w.coordinator.open(.result(result))
            }
            expect(w.opened.value.isEmpty, "a link that is not a plain web link never opens")
            expect(w.palette.hidden == 0, "and the panel stays")
        }
    }

    static func copyingALink() async {
        ExaFixture.reset(.serve(200, lite))
        await world("copy") { w in
            w.coordinator.search("swift")
            await settled(w.session)
            guard case .result(let result) = w.coordinator.launcherRows(for: "swift").first else {
                return expect(false, "a result to copy")
            }
            w.coordinator.copyLink(result)
            expect(w.copied.value == [result.url.absoluteString], "Copy Link copies the link")
            expect(w.core.events == ["message"], "and says so")
        }
    }

    static func switchingOffStopsTheSearch() async {
        ExaFixture.reset(.hold)
        await world("switch-off") { w in
            w.coordinator.search("swift")
            await expectSettles("the request is in flight") { ExaFixture.requests.count == 1 }
            w.coordinator.setEnabled(false)
            expect(!w.settings.isEnabled, "the switch is off")
            expect(!w.coordinator.isAvailable, "off is not available")
            await expectSettles("the request is stopped") { ExaFixture.stopped == 1 }
            expect(w.coordinator.launcherRows(for: "swift").isEmpty, "no rows while off")
            w.coordinator.search("swift")
            expect(ExaFixture.requests.count == 1, "Return sends nothing while off")
            ExaFixture.release(lite)
        }
    }

    static func removingTheKeyForgetsResults() async {
        ExaFixture.reset(.serve(200, lite))
        await world("remove-key") { w in
            w.coordinator.search("swift")
            await settled(w.session)
            expect(!w.coordinator.launcherRows(for: "swift").isEmpty, "results before removal")
            do { try w.settings.setKey(nil) } catch { return expect(false, "remove threw \(error)") }
            expect(w.session.results.isEmpty, "removing the key empties memory")
            expect(w.coordinator.launcherRows(for: "swift").isEmpty, "and the rows")
        }
    }

    static func removingTheKeyStopsASearch() async {
        ExaFixture.reset(.hold)
        await world("remove-key-in-flight") { w in
            w.coordinator.search("swift")
            await expectSettles("the request is in flight") { ExaFixture.requests.count == 1 }
            do { try w.settings.setKey(nil) } catch { return expect(false, "remove threw \(error)") }
            await expectSettles("the request is stopped") { ExaFixture.stopped == 1 }
            ExaFixture.release(lite)
            try? await Task.sleep(for: .milliseconds(50))
            expect(w.coordinator.launcherRows(for: "swift").isEmpty, "a late reply shows nothing")
            expect(w.session.results.isEmpty, "nor reaches memory")
        }
    }
}

// MARK: - Stand-ins for the app's own collaborators

enum DialogTone: Sendable { case neutral, success, danger }

@MainActor
final class AppCore {
    var events: [String] = []
    func showMessage(_ message: String, tone: DialogTone = .success) { events.append("message") }
}

@MainActor
final class PaletteCoordinator {
    var hidden = 0
    func hidePalette(restoreFocus: Bool = true) { hidden += 1 }
}

enum SettingsTab: Equatable { case fallbacks }

@MainActor
final class SettingsCoordinator {
    var shown: [SettingsTab] = []
    func showSettings(tab: SettingsTab? = nil) { tab.map { shown.append($0) } }
}

enum AppLauncher {
    @MainActor static func open(_ url: URL) {}
}

enum Paster {
    @MainActor static func copyPlainText(_ text: String) -> Bool { true }
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
