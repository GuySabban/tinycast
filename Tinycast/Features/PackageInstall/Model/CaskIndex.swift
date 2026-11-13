import Foundation

/// Every cask token with its 30-day install count, from Homebrew's analytics file (decision D4).
struct CaskIndex: Sendable, Codable {
    struct Entry: Sendable, Equatable, Codable {
        let token: String
        let installs: Int
    }

    enum Malformed: Error {
        case notCaskAnalytics
        case noUsableEntries
    }

    /// Most installed first, so a tie between equal matches falls to popularity.
    let entries: [Entry]
    let fetchedAt: Date
    /// Folded once per index, never per keystroke.
    private let texts: [SearchText]
    private let letterMasks: [UInt64]
    private let positions: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case entries
        case fetchedAt
    }

    init(entries: [Entry], fetchedAt: Date) {
        self.entries = entries.sorted {
            $0.installs != $1.installs ? $0.installs > $1.installs : $0.token < $1.token
        }
        self.fetchedAt = fetchedAt
        texts = self.entries.map { SearchText($0.token, transliterated: false) }
        letterMasks = texts.map { Self.letterMask($0.units) ?? 0 }
        positions = Dictionary(
            self.entries.enumerated().map { ($1.token, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            entries: try container.decode([Entry].self, forKey: .entries),
            fetchedAt: try container.decode(Date.self, forKey: .fetchedAt))
    }

    /// The file's map key is `formulae` even for casks, and its counts are strings with commas.
    private struct Analytics: Decodable {
        struct Item: Decodable {
            let count: String
        }
        let category: String
        let formulae: [String: [Item]]
    }

    static func decode(analytics data: Data, now: Date) throws(Malformed) -> CaskIndex {
        guard let analytics = try? JSONDecoder().decode(Analytics.self, from: data),
            analytics.category == "cask_install"
        else { throw .notCaskAnalytics }
        let entries = analytics.formulae.compactMap { token, items -> Entry? in
            guard CaskToken.isValid(token), !items.isEmpty else { return nil }
            var installs = 0
            for item in items {
                guard let count = Int(item.count.filter { $0 != "," }) else { return nil }
                installs += count
            }
            return Entry(token: token, installs: installs)
        }
        guard !entries.isEmpty else { throw .noUsableEntries }
        return CaskIndex(entries: entries, fetchedAt: now)
    }

    /// The token typed exactly, then tokens holding every typed word whole, then any other hit.
    private enum Tier: Int, Comparable {
        case exact
        case wholeWords
        case partial

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct Ranked {
        let tier: Tier
        let score: Int
        let position: Int

        /// Whole words rank by installs alone; a partial hit's alignment counts first.
        func precedes(_ other: Ranked) -> Bool {
            if tier != other.tier { return tier < other.tier }
            if tier == .partial, score != other.score { return score > other.score }
            return position < other.position
        }
    }

    func matches(_ name: String, limit: Int) -> [Entry] {
        let query = SearchText(name, transliterated: false)
        let words = query.units.split(whereSeparator: LauncherMatch.isSeparator)
        guard limit > 0, !words.isEmpty else { return [] }
        let dashed = words.map { String(decoding: $0, as: UTF16.self) }.joined(separator: "-")
        let exact = positions[dashed]
        guard let wanted = Self.letterMask(query.units) else { return [] }

        var ranked: [Ranked] = exact.map { [Ranked(tier: .exact, score: .max, position: $0)] } ?? []
        for position in texts.indices where position != exact {
            guard letterMasks[position] & wanted == wanted else { continue }
            let text = texts[position]
            guard let outcome = LauncherMatch.match(query, in: text),
                SearchSensitivity.medium.accepts(outcome, queryLength: query.units.count)
            else { continue }
            let tier: Tier = Self.holdsWhole(words, text.units) ? .wholeWords : .partial
            ranked.append(Ranked(tier: tier, score: outcome.value, position: position))
        }
        ranked.sort { $0.precedes($1) }
        return ranked.prefix(limit).map { entries[$0.position] }
    }

    /// A token lacking a typed letter costs one AND; nil when no token could hold the text.
    private static func letterMask(_ units: [UInt16]) -> UInt64? {
        var mask: UInt64 = 0
        for unit in units where !LauncherMatch.isSeparator(unit) {
            guard unit < 0x80, let bit = maskBits[Int(unit)] else { return nil }
            mask |= 1 << bit
        }
        return mask
    }

    private static let maskBits: [UInt64?] = {
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789@+_".utf8)
        return (0..<0x80).map { code in characters.firstIndex(of: UInt8(code)).map(UInt64.init) }
    }()

    /// "chrome" is a whole word of `google-chrome`, but only part of `google-chrome@beta`'s last.
    private static func holdsWhole(_ words: [ArraySlice<UInt16>], _ token: [UInt16]) -> Bool {
        let segments = token.split(whereSeparator: LauncherMatch.isSeparator)
        return words.allSatisfy { word in segments.contains { $0.elementsEqual(word) } }
    }
}

extension CaskIndex: Equatable {
    /// The folded texts are derived from the entries, so comparing them again proves nothing.
    static func == (lhs: CaskIndex, rhs: CaskIndex) -> Bool {
        lhs.entries == rhs.entries && lhs.fetchedAt == rhs.fetchedAt
    }
}
