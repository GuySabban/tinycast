import Foundation

/// Finds dates, links, phone numbers and addresses in recognised screen text.
enum LookDetector {
    static let itemLimit = 20
    static let allowedLinkSchemes: Set<String> = ["http", "https", "mailto"]
    static let untimedStartHour = 9
    static let defaultDuration: TimeInterval = 60 * 60

    private static let types: NSTextCheckingResult.CheckingType = [.date, .link, .phoneNumber, .address]
    private static let timePattern =
        #"\b\d{1,2}:\d{2}(\s?([ap]\.?m\.?))?(?![\w:])|\b\d{1,2}\s?[ap]\.?m\b\.?|\b(noon|midnight)\b"#
    private static let connectorPattern = #"\b(at|from|to|until|till)\b"#

    /// `now` must be the system clock: `NSDataDetector` reads "today" from it, not from here.
    static func items(in text: String, now: Date, calendar: Calendar) -> [LookItem] {
        // Not Sendable, so each call builds its own.
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        let source = text as NSString
        var seen: Set<String> = []
        var items: [LookItem] = []
        for result in detector.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let matched = source.substring(with: result.range)
            guard let value = value(of: result, matched: matched, now: now, calendar: calendar) else { continue }
            guard seen.insert(identity(of: value, matched: matched)).inserted else { continue }
            let range = result.range.location..<(result.range.location + result.range.length)
            items.append(LookItem(value: value, text: matched, range: range, line: line(around: result.range, in: source)))
            if items.count == itemLimit { break }
        }
        return items
    }

    /// The first time at or after `now` with `time`'s clock reading.
    static func nextOccurrence(of time: Date, after now: Date, calendar: Calendar) -> Date {
        var candidate = time
        while candidate < now {
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
            candidate = next
        }
        return candidate
    }

    static func hasTime(_ matched: String) -> Bool {
        matched.range(of: timePattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "3pm" or "10:00–10:30" name no day; "today at 9am" or "Fri 8pm" do.
    static func isTimeOnly(_ matched: String) -> Bool {
        guard hasTime(matched) else { return false }
        let rest = matched
            .replacingOccurrences(of: timePattern, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: connectorPattern, with: " ", options: [.regularExpression, .caseInsensitive])
        return !rest.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func value(
        of result: NSTextCheckingResult, matched: String, now: Date, calendar: Calendar
    ) -> LookItem.Value? {
        switch result.resultType {
        case .date:
            guard let date = result.date else { return nil }
            return .date(lookDate(date, duration: result.duration, matched: matched, now: now, calendar: calendar))
        case .link:
            guard let url = result.url, let scheme = url.scheme?.lowercased(), allowedLinkSchemes.contains(scheme)
            else { return nil }
            if scheme != "mailto", url.host()?.isEmpty ?? true { return nil }
            return .link(url)
        case .phoneNumber:
            return .phoneNumber(result.phoneNumber ?? matched)
        case .address:
            let components = result.addressComponents ?? [:]
            return .address(Dictionary(uniqueKeysWithValues: components.map { ($0.key.rawValue, $0.value) }))
        default:
            return nil
        }
    }

    private static func lookDate(
        _ date: Date, duration: TimeInterval, matched: String, now: Date, calendar: Calendar
    ) -> LookDate {
        let length = duration > 0 ? duration : defaultDuration
        guard hasTime(matched) else {
            let start = calendar.date(bySettingHour: untimedStartHour, minute: 0, second: 0, of: date) ?? date
            return LookDate(start: start, duration: length, hasTime: false, dayIsGuessed: false)
        }
        guard isTimeOnly(matched) else {
            return LookDate(start: date, duration: length, hasTime: true, dayIsGuessed: false)
        }
        let start = nextOccurrence(of: date, after: now, calendar: calendar)
        return LookDate(start: start, duration: length, hasTime: true, dayIsGuessed: true)
    }

    private static func identity(of value: LookItem.Value, matched: String) -> String {
        switch value {
        case .date(let date): "date \(date.start.timeIntervalSinceReferenceDate)"
        case .link(let url): "link " + url.absoluteString.lowercased().trimmingSuffix("/")
        case .phoneNumber(let number): "phone " + number.filter { $0.isASCII && ($0.isNumber || $0 == "+") }
        case .address: "address " + matched.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    private static func line(around range: NSRange, in source: NSString) -> String {
        source.substring(with: source.lineRange(for: range)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
