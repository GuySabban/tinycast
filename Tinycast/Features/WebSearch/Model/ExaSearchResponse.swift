import Foundation

/// Decodes Exa's reply leniently: one bad result is dropped, only a reply with no result list fails.
enum ExaSearchResponse {
    static func results(from data: Data, limit: Int) throws(WebSearchFailure) -> [WebSearchResult] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = object["results"] as? [Any]
        else { throw .malformedReply }
        var seen = Set<String>()
        var results: [WebSearchResult] = []
        for item in items {
            guard results.count < limit else { break }
            guard let fields = item as? [String: Any], let result = result(from: fields),
                seen.insert(result.id).inserted
            else { continue }
            results.append(result)
        }
        return results
    }

    static func publishedDate(_ text: String) -> Date? {
        for style in dateStyles {
            if let date = try? style.parse(text) { return date }
        }
        return nil
    }

    private static let dateStyles: [Date.ISO8601FormatStyle] = [
        Date.ISO8601FormatStyle(includingFractionalSeconds: true),
        Date.ISO8601FormatStyle(),
        Date.ISO8601FormatStyle().year().month().day(),
    ]

    private static func result(from fields: [String: Any]) -> WebSearchResult? {
        guard let link = fields["url"] as? String, let url = WebSearchResult.webLink(link) else {
            return nil
        }
        let host = WebSearchResult.displayHost(of: url)
        let title = WebSearchResult.cleaned(
            fields["title"] as? String ?? "", limit: WebSearchResult.titleLimit)
        let highlights = (fields["highlights"] as? [Any])?.compactMap { $0 as? String } ?? []
        let snippet = highlights.lazy
            .map { WebSearchResult.cleaned($0, limit: WebSearchResult.snippetLimit) }
            .first { !$0.isEmpty }
        return WebSearchResult(
            title: title.isEmpty ? host : title, url: url, snippet: snippet ?? "", host: host,
            published: (fields["publishedDate"] as? String).flatMap(publishedDate))
    }
}
