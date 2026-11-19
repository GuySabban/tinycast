import Foundation

/// What one search asks of the provider beyond its query; the launcher's rows use `rows`.
struct WebSearchOptions: Sendable, Equatable {
    enum SearchType: String, Sendable, CaseIterable {
        case auto, lite, fast, instant, deep
    }

    static let rows = WebSearchOptions()

    var searchType: SearchType = .lite
    var excludedDomains: [String] = []
}
