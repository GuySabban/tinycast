import Foundation

enum WebSearchRow: Sendable, Equatable, Identifiable {
    case placeholder(Int)
    case result(WebSearchResult)
    case failure(WebSearchFailure)

    var id: String {
        switch self {
        case .placeholder(let index): "web-placeholder-\(index)"
        case .result(let result): "web-" + result.id
        case .failure: "web-failure"
        }
    }

    static func placeholders(count: Int) -> [WebSearchRow] {
        (0..<max(count, 0)).map(WebSearchRow.placeholder)
    }
}
