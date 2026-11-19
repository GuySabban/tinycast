import Foundation

/// One result, already cleaned: its text is untrusted and is only ever shown as plain text.
struct WebSearchResult: Sendable, Equatable, Identifiable {
    static let titleLimit = 120
    static let snippetLimit = 280
    static let urlLimit = 2_048

    let title: String
    let url: URL
    let snippet: String
    let host: String
    let published: Date?

    var id: String { url.absoluteString }

    /// User info is refused because `https://bank.com@evil.example` reads as the wrong site.
    static func webLink(_ text: String) -> URL? {
        guard text.count <= urlLimit, let url = URL(string: text),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host(), !host.isEmpty, url.user() == nil, url.password() == nil
        else { return nil }
        return url
    }

    static func displayHost(of url: URL) -> String {
        let host = (url.host() ?? "").lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Whitespace runs become one space; controls go, and so do invisible formats bar the emoji joiner.
    static func cleaned(_ text: String, limit: Int) -> String {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                pendingSpace = !scalars.isEmpty
                continue
            }
            guard isVisible(scalar) else { continue }
            if pendingSpace { scalars.append(" ") }
            pendingSpace = false
            scalars.append(scalar)
        }
        let flat = String(scalars)
        guard flat.count > limit else { return flat }
        let kept = flat.prefix(max(limit - 1, 0)).trimmingCharacters(in: .whitespaces)
        return kept + "…"
    }

    private static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"

    private static func isVisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .surrogate, .privateUse, .unassigned: false
        case .format: scalar == zeroWidthJoiner
        default: true
        }
    }
}
