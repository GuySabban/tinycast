import Foundation

/// One Exa `/search` call; a blank query builds nothing, so it can never reach the network.
struct ExaSearchRequest: Sendable, Equatable {
    static let timeout: TimeInterval = 10
    static let maximumResults = 100

    let query: String
    let limit: Int
    let options: WebSearchOptions

    init?(query: String, limit: Int, options: WebSearchOptions = .rows) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.query = trimmed
        self.limit = min(max(limit, 1), Self.maximumResults)
        self.options = options
    }

    var body: Data {
        let domains = Self.excluded(options.excludedDomains)
        let fields = Body(
            query: query, type: options.searchType.rawValue, numResults: limit,
            excludeDomains: domains.isEmpty ? nil : domains)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Strings, integers and one flag cannot fail to encode.
        return (try? encoder.encode(fields)) ?? Data()
    }

    func urlRequest(key: String, baseURL: URL) -> URLRequest {
        var request = URLRequest(
            url: baseURL.appending(path: "search"),
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    static func excluded(_ domains: [String]) -> [String] {
        var seen = Set<String>()
        return domains
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private struct Body: Encodable {
        struct Contents: Encodable {
            let highlights = true
        }

        let query: String
        let type: String
        let numResults: Int
        let contents = Contents()
        let excludeDomains: [String]?
    }
}
