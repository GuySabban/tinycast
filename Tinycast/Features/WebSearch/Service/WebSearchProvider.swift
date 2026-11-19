import Foundation

/// The seam a second provider plugs into; each maps its own replies onto `WebSearchFailure`.
protocol WebSearchProvider: Sendable {
    func search(
        _ query: String, limit: Int, options: WebSearchOptions
    ) async throws(WebSearchFailure) -> [WebSearchResult]
}

extension WebSearchProvider {
    func search(_ query: String, limit: Int) async throws(WebSearchFailure) -> [WebSearchResult] {
        try await search(query, limit: limit, options: .rows)
    }
}
