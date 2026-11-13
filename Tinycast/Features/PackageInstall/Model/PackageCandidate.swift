import Foundation

/// What the install card shows for one query; its slot exists whatever state the index is in.
struct PackageCandidate: Sendable, Equatable {
    enum State: Sendable, Equatable {
        case loadingIndex
        /// No index in memory or on disk, and no fetch running: offline on a first launch.
        case indexUnavailable
        case noMatch
        case match(CaskIndex.Entry, alternates: [CaskIndex.Entry])
    }

    static let alternateLimit = 4

    let requestedName: String
    let state: State

    /// A refresh in flight never hides an index already in hand.
    init(requestedName: String, index: CaskIndex?, isFetchingIndex: Bool) {
        self.requestedName = requestedName
        guard let index else {
            state = isFetchingIndex ? .loadingIndex : .indexUnavailable
            return
        }
        let found = index.matches(requestedName, limit: 1 + Self.alternateLimit)
        guard let best = found.first else {
            state = .noMatch
            return
        }
        state = .match(best, alternates: Array(found.dropFirst()))
    }

    /// Only a match can be acted on; every other state leaves Return inert.
    var hasAction: Bool {
        if case .match = state { true } else { false }
    }
}
