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

    /// What Homebrew's Caskroom says about the match; nil when it records nothing.
    enum Installation: Sendable, Equatable {
        case installed
        case appMissing(String)
    }

    static let alternateLimit = 4

    let requestedName: String
    let state: State
    let installation: Installation?

    /// Keeps the index in hand during a refresh, and matches installed casks the counts lack.
    init(
        requestedName: String, index: CaskIndex?, isFetchingIndex: Bool,
        installed: [String: InstalledCask]
    ) {
        self.requestedName = requestedName
        guard let index else {
            state = isFetchingIndex ? .loadingIndex : .indexUnavailable
            installation = nil
            return
        }
        let unlisted = installed.keys.filter { !index.contains(token: $0) }.sorted()
        let found = index.matches(
            requestedName, limit: 1 + Self.alternateLimit,
            including: unlisted.map { CaskIndex.Entry(token: $0, installs: 0) })
        guard let best = found.first else {
            state = .noMatch
            installation = nil
            return
        }
        state = .match(best, alternates: Array(found.dropFirst()))
        installation = installed[best.token].map { cask in
            cask.missingAppName.map(Installation.appMissing) ?? .installed
        }
    }

    /// Only a match can be acted on; every other state leaves Return inert.
    var hasAction: Bool {
        if case .match = state { true } else { false }
    }
}
