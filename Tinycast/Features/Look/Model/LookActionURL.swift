import Foundation

/// The URLs a Look row opens to call, message or route to what it found.
enum LookActionURL {
    static func call(_ number: String) -> URL? {
        dialable(number).flatMap { URL(string: "tel:" + $0) }
    }

    static func message(_ number: String) -> URL? {
        dialable(number).flatMap { URL(string: "sms:" + $0) }
    }

    static func directions(to address: String) -> URL? {
        let place = address.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !place.isEmpty, let value = place.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return nil }
        return URL(string: "maps://?daddr=" + value)
    }

    /// A plain number or nil: screen text must not smuggle `;`, `,`, `*` or `#` dial codes.
    static func dialable(_ number: String) -> String? {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        let body = trimmed.hasPrefix("+") ? trimmed.dropFirst() : Substring(trimmed)
        guard body.allSatisfy({ ($0.isASCII && $0.isNumber) || separators.contains($0) }) else { return nil }
        let digits = body.filter { $0.isASCII && $0.isNumber }
        guard (3...20).contains(digits.count) else { return nil }
        return (trimmed.hasPrefix("+") ? "+" : "") + digits
    }

    private static let separators: Set<Character> = [" ", "-", ".", "(", ")", "\u{00A0}"]
    private static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?"))
}
