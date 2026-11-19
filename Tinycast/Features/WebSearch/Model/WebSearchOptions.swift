import Foundation

/// What one search asks of the provider beyond its query; the launcher's rows use `rows`.
struct WebSearchOptions: Sendable, Equatable {
    /// Exa's current types; it lists `fast` and `instant` as legacy, replaced by `lite`.
    enum SearchType: String, Sendable, CaseIterable {
        case auto, lite, deep
        case deepLite = "deep-lite"
    }

    static let rows = WebSearchOptions()

    var searchType: SearchType = .lite
    var excludedDomains: [String] = []
}
