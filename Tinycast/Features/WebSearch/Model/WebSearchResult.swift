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
            let host = url.host(percentEncoded: false), !host.isEmpty, url.user() == nil, url.password() == nil
        else { return nil }
        return url
    }

    /// Punycode, not Unicode: a look-alike letter in another alphabet stays visibly foreign.
    static func displayHost(of url: URL) -> String {
        let host = (url.host(percentEncoded: false) ?? "").lowercased()
        return host.hasPrefix("www.") && host.count > 4 ? String(host.dropFirst(4)) : host
    }

    /// A few marks per character covers every script; thousands on one letter is a layout attack.
    static let marksPerCharacter = 4
    /// Bounds a single character too: one emoji sequence can chain thousands of joined scalars.
    static let scalarsPerCharacter = 16

    /// Whitespace runs become one space; controls go, and so do invisible formats bar the emoji joiner.
    static func cleaned(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let budget = limit * scalarsPerCharacter
        var scalars = String.UnicodeScalarView()
        var kept = 0
        var marks = 0
        var pendingSpace = false
        var cutShort = false
        for scalar in text.unicodeScalars {
            guard kept < budget else {
                cutShort = true
                break
            }
            if scalar.properties.isWhitespace {
                pendingSpace = kept > 0
                marks = 0
                continue
            }
            guard isVisible(scalar) else { continue }
            marks = isMark(scalar) ? marks + 1 : 0
            guard marks <= marksPerCharacter else { continue }
            if pendingSpace {
                scalars.append(" ")
                kept += 1
            }
            pendingSpace = false
            scalars.append(scalar)
            kept += 1
        }
        let flat = String(scalars)
        guard cutShort || flat.count > limit else { return flat }
        let room = flat.count > limit ? limit - 1 : flat.count
        let shortened = flat.prefix(room).trimmingCharacters(in: .whitespaces)
        return String(shortened.prefix(limit - 1)) + "…"
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
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
