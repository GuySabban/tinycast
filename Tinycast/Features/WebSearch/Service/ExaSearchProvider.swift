import Foundation

/// One HTTPS call to Exa's `/search`; every way it can go wrong arrives as a `WebSearchFailure`.
struct ExaSearchProvider: WebSearchProvider {
    nonisolated static let base = URL(string: "https://api.exa.ai/")!

    private let key: String
    private let baseURL: URL
    private let session: URLSession

    init(key: String, baseURL: URL = base, protocolClasses: [AnyClass]? = nil) {
        self.key = key
        self.baseURL = baseURL
        session = protocolClasses == nil ? Self.shared : Self.session(protocolClasses: protocolClasses)
    }

    /// Cacheless, never `URLSession.shared`: Exa's terms bar keeping what it returns.
    nonisolated static func session(
        protocolClasses: [AnyClass]? = nil, timeout: TimeInterval = ExaSearchRequest.timeout
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        // A request's own timeout restarts on every byte; this caps the whole reply.
        configuration.timeoutIntervalForResource = timeout
        configuration.protocolClasses = protocolClasses
        return URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
    }

    /// One for every provider, so a key change never leaves an orphaned session behind.
    private nonisolated static let shared = session()

    @concurrent
    func search(
        _ query: String, limit: Int, options: WebSearchOptions
    ) async throws(WebSearchFailure) -> [WebSearchResult] {
        guard !key.isEmpty else { throw .missingKey }
        guard let request = ExaSearchRequest(query: query, limit: limit, options: options) else { return [] }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request.urlRequest(key: key, baseURL: baseURL))
        } catch {
            throw WebSearchFailure(transport: error)
        }
        guard !Task.isCancelled else { throw .cancelled }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw .malformedReply }
        if let failure = WebSearchFailure(status: status) { throw failure }
        return try ExaSearchResponse.results(from: data, limit: request.limit)
    }
}

/// Exa's API never redirects, so following one could only hand the key to another host.
private final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
