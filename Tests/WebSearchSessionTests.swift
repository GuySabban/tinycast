import Foundation
import Synchronization

/// A real session over a real provider, answered in-process, so no key or network is needed.
@main
@MainActor
struct WebSearchSessionTests {
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
        await searchesThroughExa()
        await mapsFailuresToRows()
        await timesOutAsOffline()
        await asksForNoKeyWithoutOne()
        await ignoresABlankQuery()
        await cancelStopsTheRequest()
        await newSearchCancelsTheOldOne()
        await dropsAStaleReply()
        await answersAKnownQueryFromMemory()
        await searchAgainAsksAgain()
        await knownQueryStillNeedsAKey()
        await forgetsBeyondTheMemoryLimit()
        await keepsTheKeyFromARedirect()
        await capsATricklingReply()
        await forgetsCookiesBetweenSearches()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - World

    static let key = "test-key-123"
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appending(path: "web-search-fixtures")
    static let lite = (try? Data(contentsOf: fixtures.appending(path: "search-lite.json"))) ?? Data()
    static let unauthorized = (try? Data(contentsOf: fixtures.appending(path: "error-401.json"))) ?? Data()

    static func exaSession(key: String = key) -> WebSearchSession {
        let provider = ExaSearchProvider(
            key: key, baseURL: URL(string: "https://exa.test/")!, protocolClasses: [ExaFixture.self])
        return WebSearchSession(limit: 5) { provider }
    }

    static func settled(_ session: WebSearchSession) async {
        await expectSettles("the search settles") {
            if case .searching = session.state { return false }
            return true
        }
    }

    // MARK: - Cases

    static func searchesThroughExa() async {
        ExaFixture.reset(.serve(200, lite))
        let session = exaSession()
        session.search("  swift ui \n")
        expect(session.state == .searching(query: "swift ui"), "a trigger starts searching at once, trimmed")
        await settled(session)
        expect(session.state == .idle, "a reply returns the session to idle")
        let found = session.results(for: "swift ui") ?? []
        expect(found.count == 5, "all five results are kept")
        expect(found.first?.host == "developer.apple.com", "in Exa's order")
        expect(session.results(for: " swift ui ") == found, "a padded query reads the same entry")
        let requests = ExaFixture.requests
        expect(requests.count == 1, "one trigger sends exactly one request")
        guard let request = requests.first else { return }
        expect(request.method == "POST" && request.path == "/search", "it posts to /search")
        expect(request.key == key, "with the key in x-api-key")
        expect(request.timeout == 10, "and a 10-second timeout")
        let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        expect(body["query"] as? String == "swift ui", "the body carries the trimmed query")
        expect(body["numResults"] as? Int == 5 && body["type"] as? String == "lite", "for five lite rows")
    }

    static func mapsFailuresToRows() async {
        let cases: [(ExaFixture.Mode, WebSearchFailure, String)] = [
            (.serve(401, unauthorized), .unauthorized, "401"),
            (.serve(402, Data("{}".utf8)), .outOfCredit, "402"),
            (.serve(429, Data("{}".utf8)), .rateLimited, "429"),
            (.serve(403, Data("{}".utf8)), .server, "403"),
            (.serve(500, Data("{}".utf8)), .server, "500"),
            (.serve(200, Data("<html>".utf8)), .malformedReply, "a reply that is not Exa's"),
            (.fail(.notConnectedToInternet), .offline, "no connection"),
            (.fail(.cannotFindHost), .offline, "an unknown host"),
        ]
        for (mode, failure, label) in cases {
            ExaFixture.reset(mode)
            let session = exaSession()
            session.search("swift")
            await settled(session)
            expect(session.state == .failed(query: "swift", failure), "\(label) maps to \(failure)")
            expect(session.results(for: "swift") == nil, "\(label) keeps nothing")
        }
    }

    static func timesOutAsOffline() async {
        ExaFixture.reset(.fail(.timedOut))
        let session = exaSession()
        session.search("swift")
        await settled(session)
        expect(session.state == .failed(query: "swift", .offline), "a timeout reads as no connection")
    }

    static func asksForNoKeyWithoutOne() async {
        ExaFixture.reset(.serve(200, lite))
        let unset = WebSearchSession(limit: 5) { nil }
        unset.search("swift")
        expect(unset.state == .failed(query: "swift", .missingKey), "no provider is a missing key")
        let blank = exaSession(key: "")
        blank.search("swift")
        await settled(blank)
        expect(blank.state == .failed(query: "swift", .missingKey), "an empty key is a missing key")
        expect(ExaFixture.requests.isEmpty, "and neither sends anything")
    }

    static func ignoresABlankQuery() async {
        ExaFixture.reset(.serve(200, lite))
        let session = exaSession()
        session.search(" \n\t")
        expect(session.state == .idle, "a blank query does nothing")
        _ = session.results(for: "swift")
        try? await Task.sleep(for: .milliseconds(50))
        expect(ExaFixture.requests.isEmpty, "neither a blank query nor reading results sends a request")
    }

    static func cancelStopsTheRequest() async {
        ExaFixture.reset(.hold)
        let session = exaSession()
        session.search("swift")
        await expectSettles("the request reaches the network") { ExaFixture.requests.count == 1 }
        session.cancel()
        expect(session.state == .idle, "cancel returns to idle at once")
        await expectSettles("cancel stops the request in flight") { ExaFixture.stopped == 1 }
        ExaFixture.release(lite)
        try? await Task.sleep(for: .milliseconds(100))
        expect(session.state == .idle, "a cancelled search never shows a failure")
        expect(session.results(for: "swift") == nil, "nor keeps a reply")
    }

    static func newSearchCancelsTheOldOne() async {
        ExaFixture.reset(.hold)
        let session = exaSession()
        session.search("first")
        await expectSettles("the first request reaches the network") { ExaFixture.requests.count == 1 }
        ExaFixture.mode(.serve(200, lite))
        session.search("second")
        await settled(session)
        await expectSettles("the newer search stops the older request") { ExaFixture.stopped == 1 }
        expect(session.results(for: "second")?.count == 5, "the newer search shows its results")
        expect(session.results(for: "first") == nil, "the older one keeps nothing")
        expect(session.state == .idle, "and leaves no failure behind")
    }

    /// A provider that answers after cancellation, as a reply already on the wire would.
    static func dropsAStaleReply() async {
        let stub = StubProvider(pausing: "first")
        let session = WebSearchSession(limit: 5) { stub }
        session.search("first")
        let paused = await stub.waitUntilPaused()
        expect(paused, "the first search is in flight")
        session.search("second")
        await settled(session)
        expect(session.results(for: "second")?.first?.title == "second", "the newer search applies")
        await stub.resume()
        try? await Task.sleep(for: .milliseconds(100))
        expect(session.results(for: "first") == nil, "a reply that outlived a newer search is dropped")
        expect(session.state == .idle, "and changes nothing on screen")
    }

    static func answersAKnownQueryFromMemory() async {
        ExaFixture.reset(.serve(200, lite))
        let session = exaSession()
        session.search("swift")
        await settled(session)
        session.search("other")
        await settled(session)
        session.search(" swift ")
        expect(session.state == .idle, "a known query does not search")
        expect(session.results(for: "swift")?.count == 5, "it shows its results again")
        try? await Task.sleep(for: .milliseconds(50))
        expect(ExaFixture.requests.count == 2, "without a request")
    }

    static func knownQueryStillNeedsAKey() async {
        ExaFixture.reset(.serve(200, lite))
        let provider = ExaSearchProvider(
            key: key, baseURL: URL(string: "https://exa.test/")!, protocolClasses: [ExaFixture.self])
        var keyed = true
        let session = WebSearchSession(limit: 5) { keyed ? provider : nil }
        session.search("swift")
        await settled(session)
        keyed = false
        session.search("swift")
        expect(session.state == .failed(query: "swift", .missingKey), "a known query without a key says so")
        expect(ExaFixture.requests.count == 1, "and sends nothing")
    }

    static func searchAgainAsksAgain() async {
        ExaFixture.reset(.serve(200, lite))
        let session = exaSession()
        session.search("swift")
        await settled(session)
        ExaFixture.mode(.fail(.notConnectedToInternet))
        session.search("swift", again: true)
        expect(session.state == .searching(query: "swift"), "Search Again searches a known query")
        await settled(session)
        expect(ExaFixture.requests.count == 2, "with a fresh request")
        expect(session.state == .failed(query: "swift", .offline), "a failed retry says so")
        expect(session.results(for: "swift")?.count == 5, "and keeps the results it already had")
    }

    static func forgetsBeyondTheMemoryLimit() async {
        ExaFixture.reset(.serve(200, lite))
        let session = exaSession()
        let limit = WebSearchSession.memoryLimit
        expect(limit == 20, "memory holds 20 queries")
        for index in 0..<limit {
            session.search("query \(index)")
            await settled(session)
        }
        expect(session.results.count == limit, "20 queries are all kept")
        session.search("query 0")
        expect(ExaFixture.requests.count == limit, "showing a kept query again costs nothing")
        session.search("query \(limit)")
        await settled(session)
        expect(session.results.count == limit, "the 21st query keeps the count at 20")
        expect(session.results(for: "query 1") == nil, "by forgetting the least recently shown")
        expect(session.results(for: "query 0") != nil, "not the one just shown again")
        session.search("query 1")
        await settled(session)
        expect(ExaFixture.requests.count == limit + 2, "a forgotten query is searched again")
    }

    static func keepsTheKeyFromARedirect() async {
        ExaFixture.reset(.redirect(URL(string: "https://elsewhere.test/search")!))
        let session = exaSession()
        session.search("swift")
        await settled(session)
        let hosts = ExaFixture.requests.map(\.host)
        expect(hosts == ["exa.test"], "a redirect is never followed, so the key stays with Exa")
        expect(session.state == .failed(query: "swift", .server), "a redirect reads as a server failure")
        expect(session.results(for: "swift") == nil, "and nothing from it is kept")
    }

    static func capsATricklingReply() async {
        let configuration = ExaSearchProvider.session().configuration
        expect(
            configuration.timeoutIntervalForResource == ExaSearchRequest.timeout,
            "the whole search is capped at the request timeout, not just idle gaps")
        ExaFixture.reset(.trickle)
        let session = ExaSearchProvider.session(protocolClasses: [ExaFixture.self], timeout: 0.5)
        let request = ExaSearchRequest(query: "swift", limit: 5, options: .rows)!
        let started = ContinuousClock.now
        var failure: WebSearchFailure?
        do {
            _ = try await session.data(for: request.urlRequest(key: key, baseURL: URL(string: "https://exa.test/")!))
        } catch {
            failure = WebSearchFailure(transport: error)
        }
        expect(failure == .offline, "a reply that trickles past the cap reads as no connection")
        expect(ContinuousClock.now - started < .seconds(3), "and ends at the cap rather than spinning on")
        await expectSettles("the trickling request is stopped") { ExaFixture.stopped == 1 }
    }

    /// URLProtocol fixtures bypass the cookie jar, so the configuration is the thing to check.
    static func forgetsCookiesBetweenSearches() async {
        let configuration = ExaSearchProvider.session().configuration
        expect(configuration.httpCookieStorage == nil, "the session keeps no cookie jar to link searches")
        expect(configuration.urlCredentialStorage == nil, "nor any credentials")
        expect(configuration.urlCache == nil, "nor a response cache")
    }
}

// MARK: - Stand-ins

actor StubProvider: WebSearchProvider {
    private let pausedQuery: String
    private var paused: CheckedContinuation<Void, Never>?

    init(pausing query: String) { pausedQuery = query }

    func search(
        _ query: String, limit: Int, options: WebSearchOptions
    ) async throws(WebSearchFailure) -> [WebSearchResult] {
        if query == pausedQuery {
            await withCheckedContinuation { paused = $0 }
        }
        let url = URL(string: "https://example.com/\(query)")!
        return [WebSearchResult(title: query, url: url, snippet: "", host: "example.com", published: nil)]
    }

    func waitUntilPaused() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while paused == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return paused != nil
    }

    func resume() {
        paused?.resume()
        paused = nil
    }
}

/// Exa as the session meets it: answers, statuses, transport errors, or a reply held back.
final class ExaFixture: URLProtocol, @unchecked Sendable {
    enum Mode {
        case serve(Int, Data)
        case fail(URLError.Code)
        /// A 307 to another host, as a compromised edge could send.
        case redirect(URL)
        /// Headers, then one byte at a time forever, so only a total cap ends it.
        case trickle
        /// Answers nothing until `release`, so a case can act while the request is in flight.
        case hold
    }

    struct Seen {
        let method: String
        let host: String
        let path: String
        let key: String?
        let timeout: TimeInterval
        let body: Data
    }

    private struct State {
        var mode: Mode = .hold
        var requests: [Seen] = []
        var held: [ExaFixture] = []
        var answered: Set<ObjectIdentifier> = []
        var halted: Set<ObjectIdentifier> = []
        /// Requests the session stopped before they were answered.
        var stopped = 0
    }

    private static let state = Mutex(State())

    static var requests: [Seen] { state.withLock { $0.requests } }
    static var stopped: Int { state.withLock { $0.stopped } }
    static func reset(_ mode: Mode) { state.withLock { $0 = State(mode: mode) } }
    static func mode(_ mode: Mode) { state.withLock { $0.mode = mode } }

    static func release(_ data: Data) {
        let held = state.withLock { state in
            defer { state.held = [] }
            return state.held
        }
        let halted = state.withLock { $0.halted }
        for fixture in held where !halted.contains(ObjectIdentifier(fixture)) { fixture.reply(status: 200, data) }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        ["exa.test", "elsewhere.test"].contains(request.url?.host)
    }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let seen = Seen(
            method: request.httpMethod ?? "", host: request.url?.host ?? "", path: request.url?.path ?? "",
            key: request.value(forHTTPHeaderField: "x-api-key"), timeout: request.timeoutInterval,
            body: Self.body(of: request))
        let mode = Self.state.withLock { state in
            state.requests.append(seen)
            if case .hold = state.mode { state.held.append(self) }
            return state.mode
        }
        switch mode {
        case .serve(let status, let data): reply(status: status, data)
        case .fail(let code):
            Self.state.withLock { _ = $0.answered.insert(ObjectIdentifier(self)) }
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .redirect(let target): redirect(to: target)
        case .trickle: trickle()
        case .hold: break
        }
    }

    override func stopLoading() {
        let me = ObjectIdentifier(self)
        Self.state.withLock { state in
            state.halted.insert(me)
            if !state.answered.contains(me) { state.stopped += 1 }
        }
    }

    private func redirect(to target: URL) {
        Self.state.withLock { _ = $0.answered.insert(ObjectIdentifier(self)) }
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: 307, httpVersion: nil, headerFields: ["Location": target.absoluteString])
        else { return }
        var next = request
        next.url = target
        client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func trickle() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let me = ObjectIdentifier(self)
        Thread.detachNewThread { [self] in
            while !Self.state.withLock({ $0.halted.contains(me) }) {
                client?.urlProtocol(self, didLoad: Data("{".utf8))
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }

    /// URLSession hands a protocol the body as a stream, never as `httpBody`.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private func reply(status: Int, _ data: Data) {
        let me = ObjectIdentifier(self)
        Self.state.withLock { _ = $0.answered.insert(me) }
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
