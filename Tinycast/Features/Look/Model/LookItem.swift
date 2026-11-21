import Foundation

/// One thing found in a Look's text, carrying what its row needs to act on it.
struct LookItem: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case date, link, phoneNumber, address
    }

    enum Value: Sendable, Hashable {
        case date(LookDate)
        case link(URL)
        case phoneNumber(String)
        /// `NSTextCheckingKey` raw values ("Street", "City", "ZIP", …) to the matched parts.
        case address([String: String])
    }

    let value: Value
    /// As matched, so a wrong row shows what it was made from.
    let text: String
    /// UTF-16 offsets into the Look's text.
    let range: Range<Int>
    /// The trimmed line holding the match: an event's title comes from it.
    let line: String

    var kind: Kind {
        switch value {
        case .date: .date
        case .link: .link
        case .phoneNumber: .phoneNumber
        case .address: .address
        }
    }
}
