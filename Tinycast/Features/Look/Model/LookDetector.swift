import Foundation

/// Finds dates, links, phone numbers and addresses in recognised screen text.
enum LookDetector {
    static let itemLimit = 20
    static let allowedLinkSchemes: Set<String> = ["http", "https", "mailto"]
    static let untimedStartHour = 9
    static let defaultDuration: TimeInterval = 60 * 60

    private static let types: NSTextCheckingResult.CheckingType = [.date, .link, .phoneNumber, .address]
    private static let noonPattern = #"\b(noon|midday)\b|\b12([:.h]00|\s?(p\.?m|o'?clock|h\b))"#
    private static let dayPattern = #"""
        \b(today|tonight|tomorrow|yesterday|this\s+(morning|afternoon|evening)\#
        |mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun\#
        |monday|tuesday|wednesday|thursday|friday|saturday|sunday\#
        |jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec\#
        |january|february|march|april|june|july|august|september|october|november|december)\b\#
        |\b\d{4}[./-]\d{1,2}[./-]\d{1,2}(?!\d)|\b\d{1,2}/\d{1,2}\b|\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b|\b\d{1,2}(st|nd|rd|th)\b
        """#

    /// `now` must be the system clock: `NSDataDetector` reads "today" from it (D44).
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

    /// The detector reads a date with no time as 12:00, so only a written noon keeps that clock.
    static func hasTime(_ date: Date, matched: String, calendar: Calendar) -> Bool {
        let clock = calendar.dateComponents([.hour, .minute, .second], from: date)
        guard clock.hour == 12, clock.minute == 0, clock.second == 0 else { return true }
        return matched.range(of: noonPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "today at 9am", "Fri at 3" or "3/12" name a day; "3pm", "8 o'clock" or "10-11am" don't.
    static func namesADay(_ matched: String) -> Bool {
        matched.range(of: dayPattern, options: [.regularExpression, .caseInsensitive]) != nil
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
        guard hasTime(date, matched: matched, calendar: calendar) else {
            let start = calendar.date(bySettingHour: untimedStartHour, minute: 0, second: 0, of: date) ?? date
            return LookDate(start: start, duration: length, hasTime: false, dayIsGuessed: false)
        }
        // The detector puts a time with no day on today, even one already past.
        guard calendar.isDate(date, inSameDayAs: now), !namesADay(matched) else {
            return LookDate(start: date, duration: length, hasTime: true, dayIsGuessed: false)
        }
        let start = nextOccurrence(of: date, after: now, calendar: calendar)
        return LookDate(start: start, duration: length, hasTime: true, dayIsGuessed: true)
    }

    private static func identity(of value: LookItem.Value, matched: String) -> String {
        switch value {
        case .date(let date): "date \(date.start.timeIntervalSinceReferenceDate)"
        case .link(let url): "link " + linkIdentity(url)
        case .phoneNumber(let number):
            "phone " + number.compactMap { $0 == "+" ? "+" : $0.wholeNumberValue.map(String.init) }.joined()
        case .address: "address " + matched.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    /// Only the scheme and host are case-insensitive: `/Report` and `/report` are different pages.
    private static func linkIdentity(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path.hasSuffix("/") { components.path.removeLast() }
        return components.string ?? url.absoluteString
    }

    private static func line(around range: NSRange, in source: NSString) -> String {
        source.substring(with: source.lineRange(for: range)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
