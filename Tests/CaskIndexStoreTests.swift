import Foundation
import Synchronization

@main
@MainActor
struct CaskIndexStoreTests {
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

    static func main() async throws {
        try await fetchesOnFirstLaunch()
        try await startsFromAFreshCacheWithoutARequest()
        try await refreshesAStaleCache()
        try await keepsTheCacheOffline()
        try await ignoresAMalformedReply()
        try await ignoresAFailedStatus()
        try await reportsAnUnavailableIndexOfflineOnFirstLaunch()
        try await replacesACorruptCache()
        try await dropsAReplyThatArrivesAfterStop()
        try await retriesAfterAFailure()
        try await refreshesOnSchedule()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static let base = URL(string: "https://brew.test/api/")!
    static let analyticsPath = "/api/analytics/cask-install/homebrew-cask/30d.json"
    static let now = Date(timeIntervalSinceReferenceDate: 816_000_000)

    static func analytics() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: "Tests/package-fixtures/cask-install-30d.json"))
    }

    /// Its own folder per case, so parallel harnesses never share a cache.
    static func scratchCache() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "CaskIndexStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Caches/cask-index.json")
    }

    static func writeCache(_ index: CaskIndex, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(index).write(to: url)
    }

    static let oldIndex = CaskIndex(entries: [.init(token: "old-cask", installs: 7)], fetchedAt: now - 3_600)
    static let staleIndex = CaskIndex(
        entries: [.init(token: "old-cask", installs: 7)], fetchedAt: now - 25 * 3_600)

    static func store(
        cache: URL, schedule: CaskIndexStore.Schedule = .standard, clock: @escaping () -> Date = { now }
    ) -> CaskIndexStore {
        CaskIndexStore(
            cacheURL: cache, baseURL: base, protocolClasses: [HomebrewFixture.self], schedule: schedule,
            now: clock)
    }

    /// Bounded, so a store that never settles fails the case instead of hanging the suite.
    static func expectSettles(_ message: String, within seconds: Double = 5, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition() {
            guard ContinuousClock.now < deadline else { return expect(false, message) }
            try? await Task.sleep(for: .milliseconds(10))
        }
        expect(true, message)
    }

    /// Long enough for a request the store should not make to have been made.
    static func quietPeriod() async { try? await Task.sleep(for: .milliseconds(300)) }

    static func fetchesOnFirstLaunch() async throws {
        HomebrewFixture.reset(.serve(try analytics()))
        let cache = try scratchCache()
        let store = store(cache: cache)
        expect(store.index == nil, "nothing in memory before start")
        store.start()
        expect(store.isFetching, "loading from the first moment, so the card never says unavailable")
        expect(
            PackageCandidate(requestedName: "blender", index: store.index, isFetchingIndex: store.isFetching)
                .state == .loadingIndex,
            "the card reads loading while the first fetch runs")
        await expectSettles("the first fetch lands") { store.index != nil && !store.isFetching }
        expect(HomebrewFixture.paths == [analyticsPath], "one request, for the install-count file")
        expect(store.index?.entries.count == 6_043, "the whole file is indexed")
        expect(store.index?.fetchedAt == now, "stamped with the injected clock")
        expect(store.revision == 1, "one new index, one revision")
        let cached = try JSONDecoder().decode(CaskIndex.self, from: Data(contentsOf: cache))
        expect(cached == store.index, "the cache holds what was fetched")
        store.stop()
    }

    static func startsFromAFreshCacheWithoutARequest() async throws {
        HomebrewFixture.reset(.serve(try analytics()))
        let cache = try scratchCache()
        try writeCache(oldIndex, to: cache)
        let store = store(cache: cache)
        store.start()
        await expectSettles("the cache loads") { store.index != nil && !store.isFetching }
        await quietPeriod()
        expect(store.index == oldIndex, "the cached index is served")
        expect(HomebrewFixture.paths.isEmpty, "a cache younger than a day sends no request")
        expect(store.revision == 1, "loading the cache is one revision")
        store.stop()
    }

    static func refreshesAStaleCache() async throws {
        HomebrewFixture.reset(.serve(try analytics()))
        let cache = try scratchCache()
        try writeCache(staleIndex, to: cache)
        let store = store(cache: cache)
        store.start()
        await expectSettles("the stale cache still answers at once") { store.index != nil }
        await expectSettles("then is replaced") { store.index?.entries.count == 6_043 && !store.isFetching }
        expect(HomebrewFixture.paths.count == 1, "one request")
        expect(store.revision == 2, "the cache and the fetch are a revision each")
        let cached = try JSONDecoder().decode(CaskIndex.self, from: Data(contentsOf: cache))
        expect(cached.fetchedAt == now, "the cache file is replaced too")
        store.stop()
    }

    static func keepsTheCacheOffline() async throws {
        HomebrewFixture.reset(.offline)
        let cache = try scratchCache()
        try writeCache(staleIndex, to: cache)
        let before = try Data(contentsOf: cache)
        let store = store(cache: cache)
        store.start()
        await expectSettles("the fetch is tried") { HomebrewFixture.paths.count == 1 && !store.isFetching }
        expect(store.index == staleIndex, "offline keeps serving the stale index")
        expect(try Data(contentsOf: cache) == before, "and leaves the cache file alone")
        store.stop()
    }

    static func ignoresAMalformedReply() async throws {
        HomebrewFixture.reset(.serve(Data("<html><body>Bad gateway</body></html>".utf8)))
        let cache = try scratchCache()
        try writeCache(staleIndex, to: cache)
        let before = try Data(contentsOf: cache)
        let store = store(cache: cache)
        store.start()
        await expectSettles("the fetch is tried") { HomebrewFixture.paths.count == 1 && !store.isFetching }
        expect(store.index == staleIndex, "an HTML page served as 200 is not an index")
        expect(store.revision == 1, "and is no revision")
        expect(try Data(contentsOf: cache) == before, "nor written to the cache")
        store.stop()
    }

    static func ignoresAFailedStatus() async throws {
        HomebrewFixture.reset(.status(503, try analytics()))
        let cache = try scratchCache()
        try writeCache(staleIndex, to: cache)
        let store = store(cache: cache)
        store.start()
        await expectSettles("the fetch is tried") { HomebrewFixture.paths.count == 1 && !store.isFetching }
        expect(store.index == staleIndex, "a 503 is ignored even when its body would decode")
        store.stop()
    }

    static func reportsAnUnavailableIndexOfflineOnFirstLaunch() async throws {
        HomebrewFixture.reset(.offline)
        let cache = try scratchCache()
        let store = store(cache: cache)
        store.start()
        await expectSettles("the fetch is tried") { HomebrewFixture.paths.count == 1 && !store.isFetching }
        expect(store.index == nil, "no index")
        expect(
            PackageCandidate(requestedName: "blender", index: store.index, isFetchingIndex: store.isFetching)
                .state == .indexUnavailable,
            "the card says unavailable, not loading forever")
        expect(!FileManager.default.fileExists(atPath: cache.path), "no cache file is invented")
        store.stop()
    }

    static func replacesACorruptCache() async throws {
        HomebrewFixture.reset(.serve(try analytics()))
        let cache = try scratchCache()
        try FileManager.default.createDirectory(
            at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"entries\":[{\"tok".utf8).write(to: cache)
        let store = store(cache: cache)
        store.start()
        await expectSettles("fetched instead") { store.index?.entries.count == 6_043 && !store.isFetching }
        expect(HomebrewFixture.paths.count == 1, "a corrupt cache counts as none")
        expect((try? JSONDecoder().decode(CaskIndex.self, from: Data(contentsOf: cache))) != nil, "rewritten")
        store.stop()
    }

    static func dropsAReplyThatArrivesAfterStop() async throws {
        HomebrewFixture.reset(.hold)
        let cache = try scratchCache()
        let store = store(cache: cache)
        store.start()
        await expectSettles("the request is in flight") { HomebrewFixture.paths.count == 1 }
        store.stop()
        expect(!store.isFetching, "stop ends the loading state at once")
        HomebrewFixture.release(try analytics())
        await quietPeriod()
        expect(store.index == nil, "a reply after stop is never applied")
        expect(!FileManager.default.fileExists(atPath: cache.path), "nor cached")

        HomebrewFixture.reset(.serve(try analytics()))
        store.start()
        await expectSettles("a restart fetches again") { store.index?.entries.count == 6_043 }
        store.stop()
    }

    static func retriesAfterAFailure() async throws {
        HomebrewFixture.reset(.offline)
        let cache = try scratchCache()
        let store = store(cache: cache, schedule: .init(refresh: 3_600, retry: 0.2))
        store.start()
        await expectSettles("the first try fails") { HomebrewFixture.paths.count == 1 && !store.isFetching }
        HomebrewFixture.mode(.serve(try analytics()))
        await expectSettles("the retry lands once the network is back") { store.index != nil }
        expect(HomebrewFixture.paths.count == 2, "exactly one retry")
        store.stop()
    }

    /// The real clock, because the schedule measures age from the index's own timestamp.
    static func refreshesOnSchedule() async throws {
        HomebrewFixture.reset(.serve(try analytics()))
        let cache = try scratchCache()
        let store = store(cache: cache, schedule: .init(refresh: 0.3, retry: 3_600), clock: Date.init)
        store.start()
        await expectSettles("the first fetch") { store.revision == 1 }
        await expectSettles("a second once the refresh interval passes") { store.revision == 2 }
        expect(HomebrewFixture.paths.count == 2, "one request per interval")
        store.stop()
        await quietPeriod()
        expect(HomebrewFixture.paths.count == 2, "a stopped store sends nothing more")
    }
}

/// URL loading owns each instance; the shared reply and request log are guarded by a mutex.
private final class HomebrewFixture: URLProtocol, @unchecked Sendable {
    enum Mode {
        case serve(Data)
        case status(Int, Data)
        case offline
        /// Answers nothing until `release`, so a case can act while the request is in flight.
        case hold
    }

    private struct State {
        var mode: Mode = .offline
        var paths: [String] = []
        var held: [HomebrewFixture] = []
    }

    private static let state = Mutex(State())

    static var paths: [String] { state.withLock { $0.paths } }
    static func reset(_ mode: Mode) { state.withLock { $0 = State(mode: mode) } }
    static func mode(_ mode: Mode) { state.withLock { $0.mode = mode } }

    static func release(_ data: Data) {
        let held = state.withLock { state in
            defer { state.held = [] }
            return state.held
        }
        for fixture in held { fixture.reply(status: 200, data) }
    }

    override static func canInit(with request: URLRequest) -> Bool { request.url?.host == "brew.test" }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let mode = Self.state.withLock { state in
            state.paths.append(request.url?.path ?? "")
            if case .hold = state.mode { state.held.append(self) }
            return state.mode
        }
        switch mode {
        case .serve(let data): reply(status: 200, data)
        case .status(let code, let data): reply(status: code, data)
        case .offline: client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .hold: break
        }
    }

    override func stopLoading() {}

    private func reply(status: Int, _ data: Data) {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
