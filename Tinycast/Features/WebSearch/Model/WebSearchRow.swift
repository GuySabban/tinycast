import Foundation

enum WebSearchRow: Sendable, Equatable, Identifiable {
    case placeholder(Int)
    case result(WebSearchResult)
    case failure(WebSearchFailure)
    /// An answered search that found nothing, so it never looks like one that did not run.
    case noResults

    var id: String {
        switch self {
        case .placeholder(let index): "web-placeholder-\(index)"
        case .result(let result): "web-" + result.id
        case .failure: "web-failure"
        case .noResults: "web-no-results"
        }
    }

    static func placeholders(count: Int) -> [WebSearchRow] {
        (0..<max(count, 0)).map(WebSearchRow.placeholder)
    }

    /// A placeholder past the first is skipped: fewer rows may arrive and hand its index to another.
    /// Positions are relative to the section's first row; nil leaves the move as it is.
    static func landing(at target: Int, from current: Int, in rows: [WebSearchRow]) -> Int? {
        guard target > 0, rows.indices.contains(target), case .placeholder = rows[target] else { return nil }
        return target > current ? rows.count : 0
    }
}
