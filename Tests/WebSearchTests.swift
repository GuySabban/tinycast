import Foundation

@main
@MainActor
struct WebSearchTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        do {
            if try condition() {
                passes += 1
                return
            }
        } catch {
            print("  error: \(error)")
        }
        failures += 1
        print("FAIL: \(message)")
    }

    static func main() async throws {
        try buildsTheRowsRequest()
        try optionsReachTheBody()
        refusesABlankQuery()
        try clampsTheLimit()
        await providerDefaultsItsOptions()
        try decodesAReply()
        try cleansUntrustedText()
        try keepsOnlyWebLinks()
        try fallsBackToTheHost()
        try respectsTheLimit()
        rejectsMalformedReplies()
        mapsStatusesAndTransportErrors()
        rowIdentitiesAreDistinct()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Fixtures

    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appending(path: "web-search-fixtures")

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appending(path: name))
    }

    static func json(_ data: Data?) throws -> [String: Any] {
        guard let data, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    static func decoded(_ name: String, limit: Int = 10) throws -> [WebSearchResult] {
        let data = try fixture(name)
        do {
            return try ExaSearchResponse.results(from: data, limit: limit)
        } catch {
            print("  decode failed: \(error)")
            return []
        }
    }

    static func failure(decoding data: Data) -> WebSearchFailure? {
        do {
            _ = try ExaSearchResponse.results(from: data, limit: 5)
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Request

    static func buildsTheRowsRequest() throws {
        let base = URL(string: "https://api.exa.ai")!
        guard let request = ExaSearchRequest(query: "  swiftui lists \n", limit: 5) else {
            expect(false, "a real query builds a request")
            return
        }
        let urlRequest = request.urlRequest(key: "test-key", baseURL: base)
        expect(urlRequest.url?.absoluteString == "https://api.exa.ai/search", "posts to /search")
        expect(urlRequest.httpMethod == "POST", "is a POST")
        expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "test-key", "key travels in x-api-key")
        expect(urlRequest.value(forHTTPHeaderField: "Authorization") == nil, "no Authorization header")
        expect(
            urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json",
            "declares a JSON body")
        expect(urlRequest.timeoutInterval == ExaSearchRequest.timeout, "carries the request timeout")
        expect(urlRequest.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData, "never reads a cache")
        let body = String(bytes: request.body, encoding: .utf8) ?? ""
        expect(
            body == #"{"contents":{"highlights":true},"numResults":5,"query":"swiftui lists","type":"lite"}"#,
            "default body is the planned rows request, got \(body)")
        expect(urlRequest.httpBody == request.body, "the URL request carries the body")
        let nested = request.urlRequest(key: "k", baseURL: URL(string: "http://127.0.0.1:8123/v1/")!)
        expect(nested.url?.absoluteString == "http://127.0.0.1:8123/v1/search", "base URL path is kept")
    }

    static func optionsReachTheBody() throws {
        let options = WebSearchOptions(
            searchType: .auto,
            excludedDomains: ["  Example.COM ", "", "example.com", "*.ads.net", " \n", "Docs.Example.com/path"])
        let request = ExaSearchRequest(query: "brew cask", limit: 3, options: options)
        let body = try json(request?.body)
        expect(body["type"] as? String == "auto", "search type reaches the body")
        expect(body["numResults"] as? Int == 3, "limit reaches the body")
        expect(
            body["excludeDomains"] as? [String] == ["example.com", "*.ads.net", "docs.example.com/path"],
            "excluded domains are trimmed, lowercased, deduplicated: \(body["excludeDomains"] ?? "none")")
        let plain = try json(ExaSearchRequest(query: "brew cask", limit: 3)?.body)
        expect(plain["excludeDomains"] == nil, "no excluded domains leaves the key out")
        let blanks = WebSearchOptions(excludedDomains: [" ", ""])
        let blankBody = try json(ExaSearchRequest(query: "q", limit: 3, options: blanks)?.body)
        expect(blankBody["excludeDomains"] == nil, "only blank domains leaves the key out")
        expect(WebSearchOptions.rows == WebSearchOptions(), "the rows options are the defaults")
        expect(WebSearchOptions.rows.searchType == .lite, "rows search with lite")
        expect(WebSearchOptions.rows.excludedDomains.isEmpty, "rows exclude nothing")
        for type in WebSearchOptions.SearchType.allCases {
            let typed = try json(
                ExaSearchRequest(query: "q", limit: 1, options: WebSearchOptions(searchType: type))?.body)
            expect(typed["type"] as? String == type.rawValue, "\(type) serializes as its raw value")
        }
    }

    static func refusesABlankQuery() {
        expect(ExaSearchRequest(query: "", limit: 5) == nil, "empty query builds nothing")
        expect(ExaSearchRequest(query: "  \n\t ", limit: 5) == nil, "whitespace query builds nothing")
        expect(ExaSearchRequest(query: "a", limit: 5)?.query == "a", "one character is a query")
    }

    static func clampsTheLimit() throws {
        let low = try json(ExaSearchRequest(query: "q", limit: 0)?.body)
        expect(low["numResults"] as? Int == 1, "limit below one asks for one")
        let high = try json(ExaSearchRequest(query: "q", limit: 5_000)?.body)
        expect(high["numResults"] as? Int == ExaSearchRequest.maximumResults, "limit is capped")
    }

    static func providerDefaultsItsOptions() async {
        let provider = RecordingProvider()
        do {
            _ = try await provider.search("q", limit: 5)
            let tuned = WebSearchOptions(searchType: .fast, excludedDomains: ["a.com"])
            _ = try await provider.search("q", limit: 5, options: tuned)
        } catch {
            expect(false, "recording provider never throws: \(error)")
        }
        let seen = await provider.recorder.options
        expect(seen.first == .rows, "a caller that omits options gets the rows defaults")
        expect(seen.last?.searchType == .fast, "a caller's options pass through")
        expect(seen.count == 2, "both calls reached the provider")
    }

    // MARK: - Reply

    static func decodesAReply() throws {
        let results = try decoded("search-lite.json")
        expect(results.count == 5, "five results decode, got \(results.count)")
        guard results.count == 5 else { return }
        let first = results[0]
        expect(first.title == "SwiftUI | Apple Developer Documentation", "title decodes")
        expect(first.url.absoluteString == "https://developer.apple.com/documentation/swiftui", "url decodes")
        expect(first.host == "developer.apple.com", "host is the URL's host")
        expect(first.snippet.hasPrefix("SwiftUI provides views"), "first highlight is the snippet")
        expect(first.id == first.url.absoluteString, "id is the URL")
        let september = DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: .gmt, year: 2026, month: 9, day: 15
        ).date
        expect(first.published == september, "fractional ISO date parses")
        expect(results[1].host == "hackingwithswift.com", "a leading www. is dropped from the host")
        expect(results[1].published != nil, "milliseconds parse")
        expect(results[2].published != nil, "a date without fractional seconds parses")
        expect(results[2].snippet.isEmpty, "no highlights is an empty snippet")
        expect(results[3].published == nil, "a missing date is nil")
        expect(results[4].published == nil, "an unparseable date is nil, not a failure")
        expect(ExaSearchResponse.publishedDate("2026-01-05") != nil, "a bare day parses")
        expect(try decoded("search-empty.json").isEmpty, "an empty result list is no results")
    }

    static func cleansUntrustedText() throws {
        let results = try decoded("search-hostile.json", limit: 50)
        guard let first = results.first else {
            expect(false, "hostile fixture decodes")
            return
        }
        expect(first.title == "Line one tabnuleviliso spaced out", "title cleaned, got \(first.title)")
        expect(first.snippet == "snippet withbell", "snippet cleaned, got \(first.snippet)")
        let control = first.title.unicodeScalars.contains {
            $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
        }
        expect(!control, "no control or format characters survive")
        guard let long = results.first(where: { $0.url.path() == "/long" }) else {
            expect(false, "long-text result is kept")
            return
        }
        expect(long.title.count == WebSearchResult.titleLimit, "title is capped at \(long.title.count)")
        expect(long.title.hasSuffix("…"), "a cut title ends in an ellipsis")
        expect(long.snippet.count == WebSearchResult.snippetLimit, "snippet is capped")
        expect(long.snippet.hasSuffix("…"), "a cut snippet ends in an ellipsis")
        expect(WebSearchResult.cleaned("  short  ", limit: 10) == "short", "short text is only trimmed")
        expect(WebSearchResult.cleaned("abcdef", limit: 6) == "abcdef", "text at the limit is kept whole")
        expect(WebSearchResult.cleaned("abcdefg", limit: 6) == "abcde…", "the ellipsis fits in the limit")
        expect(WebSearchResult.cleaned("👍🏽👍🏽👍🏽", limit: 2) == "👍🏽…", "the cut keeps whole characters")
        expect(WebSearchResult.cleaned("a\u{200D}b", limit: 10) == "a\u{200D}b", "the emoji joiner is kept")
        expect(WebSearchResult.cleaned("a\u{E0041}b", limit: 10) == "ab", "invisible tag characters go")
        expect(WebSearchResult.cleaned("abc defgh", limit: 5) == "abc…", "no space before the ellipsis")
    }

    static func keepsOnlyWebLinks() throws {
        let results = try decoded("search-hostile.json", limit: 50)
        let links = results.map(\.url.absoluteString)
        expect(links.allSatisfy { $0.lowercased().hasPrefix("http") }, "only http(s) links survive: \(links)")
        expect(!links.contains { $0.contains("javascript") }, "javascript: is dropped")
        expect(!links.contains { $0.contains("passwd") }, "file: is dropped")
        expect(!links.contains { $0.contains("evil") }, "a link with user info is dropped")
        expect(!links.contains { $0.contains("nohost") }, "a link without a host is dropped")
        expect(!links.contains { $0.contains("/just/a/path") }, "a relative link is dropped")
        expect(!links.contains { $0.count > WebSearchResult.urlLimit }, "an overlong link is dropped")
        expect(links.filter { $0 == "https://example.com/a" }.count == 1, "a repeated link is kept once")
        expect(results.first?.snippet == "snippet withbell", "the first copy of a repeated link wins")
        let upper = results.first { $0.title == "Upper" }
        expect(upper?.host == "example.org", "an upper-case scheme and host are accepted, host lowercased")
        expect(results.count == 6, "six of the hostile results survive, got \(results.count)")
        expect(WebSearchResult.webLink("https://example.com") != nil, "a bare https link passes")
        expect(WebSearchResult.webLink("http://example.com/x?y=1#z") != nil, "query and fragment pass")
        expect(WebSearchResult.webLink("blob:https://example.com/id") == nil, "blob: is dropped")
        expect(WebSearchResult.webLink(" https://example.com") == nil, "a padded link is not repaired")
    }

    static func fallsBackToTheHost() throws {
        let results = try decoded("search-hostile.json", limit: 50)
        let untitled = results.first { $0.url.host() == "www.untitled.example" }
        expect(untitled?.title == "untitled.example", "a blank title falls back to the host")
        expect(untitled?.snippet == "second wins", "the first non-blank highlight is the snippet")
        let missing = results.first { $0.host == "notitle.example" }
        expect(missing?.title == "notitle.example", "a missing title falls back to the host")
        expect(missing?.snippet == "", "highlights that are not a list are no snippet")
        let numbered = results.first { $0.host == "numbertitle.example" }
        expect(numbered?.title == "numbertitle.example", "a non-string title falls back to the host")
        expect(numbered?.snippet == "text after a number", "non-string highlights are skipped")
    }

    static func respectsTheLimit() throws {
        expect(try decoded("search-lite.json", limit: 2).count == 2, "decoding stops at the limit")
        expect(try decoded("search-lite.json", limit: 0).isEmpty, "a zero limit keeps nothing")
    }

    static func rejectsMalformedReplies() {
        let cases: [(String, String)] = [
            ("not json", "plain text"),
            ("[]", "a top-level array"),
            (#"{"requestId":"x"}"#, "a reply without results"),
            (#"{"results":{"title":"x"}}"#, "results that are not a list"),
            ("", "an empty body"),
        ]
        for (body, label) in cases {
            expect(failure(decoding: Data(body.utf8)) == .malformedReply, "\(label) is a malformed reply")
        }
        let error = (try? fixture("error-401.json")) ?? Data()
        expect(failure(decoding: error) == .malformedReply, "an error envelope is not results")
    }

    // MARK: - Failures and rows

    static func mapsStatusesAndTransportErrors() {
        expect(WebSearchFailure(status: 200) == nil, "200 is not a failure")
        expect(WebSearchFailure(status: 204) == nil, "2xx is not a failure")
        expect(WebSearchFailure(status: 401) == .unauthorized, "401 is unauthorized")
        expect(WebSearchFailure(status: 403) == .unauthorized, "403 is unauthorized")
        expect(WebSearchFailure(status: 402) == .outOfCredit, "402 is out of credit")
        expect(WebSearchFailure(status: 429) == .rateLimited, "429 is rate limited")
        expect(WebSearchFailure(status: 400) == .server, "another 4xx is a server failure")
        expect(WebSearchFailure(status: 500) == .server, "500 is a server failure")
        expect(WebSearchFailure(status: 503) == .server, "503 is a server failure")
        expect(WebSearchFailure(status: 301) == .server, "an unfollowed redirect is a server failure")
        expect(WebSearchFailure(transport: URLError(.cancelled)) == .cancelled, "cancel is cancelled")
        expect(WebSearchFailure(transport: URLError(.notConnectedToInternet)) == .offline, "offline")
        expect(WebSearchFailure(transport: URLError(.timedOut)) == .offline, "a timeout reads as offline")
        expect(WebSearchFailure(transport: URLError(.cannotFindHost)) == .offline, "DNS reads as offline")
        expect(WebSearchFailure(transport: CancellationError()) == .cancelled, "task cancel is cancelled")
    }

    static func rowIdentitiesAreDistinct() {
        let result = WebSearchResult(
            title: "T", url: URL(string: "https://example.com/a")!, snippet: "", host: "example.com",
            published: nil)
        let placeholders = WebSearchRow.placeholders(count: 5)
        expect(placeholders.count == 5, "five placeholders")
        let rows = placeholders + [.result(result), .failure(.offline)]
        expect(Set(rows.map(\.id)).count == rows.count, "every row has its own id")
        expect(WebSearchRow.result(result).id == "web-https://example.com/a", "a result row's id is its URL")
        expect(WebSearchRow.failure(.server).id == WebSearchRow.failure(.offline).id, "one failure row")
        expect(WebSearchRow.placeholders(count: 0).isEmpty, "zero placeholders")
        expect(WebSearchRow.placeholders(count: -1).isEmpty, "a negative count is none")
    }
}

actor OptionsRecorder {
    var options: [WebSearchOptions] = []
    func record(_ value: WebSearchOptions) { options.append(value) }
}

struct RecordingProvider: WebSearchProvider {
    let recorder = OptionsRecorder()

    func search(
        _ query: String, limit: Int, options: WebSearchOptions
    ) async throws(WebSearchFailure) -> [WebSearchResult] {
        await recorder.record(options)
        return []
    }
}
