import Foundation

/// The launcher's searches: one request at a time, results kept in memory and never on disk.
@MainActor
@Observable
final class WebSearchSession {
    typealias ProviderSource = @MainActor () -> (any WebSearchProvider)?

    enum State: Equatable {
        case idle
        case searching(query: String)
        case failed(query: String, WebSearchFailure)
    }

    /// Exa's terms allow only temporary copies for display, so memory holds a handful of queries.
    static let memoryLimit = 20

    private(set) var state: State = .idle
    /// The last `memoryLimit` searched queries and their results, keyed by `key(for:)`.
    private(set) var results: [String: [WebSearchResult]] = [:]

    @ObservationIgnored private var recency: [String] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Identifies the current search, so a reply that outlived a newer one or a cancel is dropped.
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private let provider: ProviderSource
    @ObservationIgnored private let limit: Int

    /// The provider is asked for on each search, so a key stored or removed applies at once.
    init(limit: Int, provider: @escaping ProviderSource) {
        self.limit = limit
        self.provider = provider
    }

    nonisolated static func key(for query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func results(for query: String) -> [WebSearchResult]? {
        results[Self.key(for: query)]
    }

    /// A query already in memory answers from there without a request, unless `again` asks for one.
    func search(_ query: String, again: Bool = false) {
        let key = Self.key(for: query)
        guard !key.isEmpty else { return }
        cancel()
        guard let provider = provider() else {
            state = .failed(query: key, .missingKey)
            return
        }
        if !again, results[key] != nil {
            remember(key)
            return
        }
        state = .searching(query: key)
        let current = revision
        let limit = limit
        task = Task { [weak self] in
            let outcome = await Self.fetch(key, limit: limit, from: provider)
            self?.apply(outcome, for: key, revision: current)
        }
    }

    /// Drops every remembered query, for when the key that fetched them is removed.
    func forget() {
        cancel()
        results = [:]
        recency = []
    }

    func cancel() {
        revision &+= 1
        task?.cancel()
        task = nil
        if state != .idle { state = .idle }
    }

    private func apply(_ outcome: Result<[WebSearchResult], WebSearchFailure>, for key: String, revision: Int) {
        guard revision == self.revision, state == .searching(query: key) else { return }
        task = nil
        switch outcome {
        case .success(let found):
            results[key] = found
            remember(key)
            state = .idle
        case .failure(.cancelled):
            state = .idle
        case .failure(let failure):
            state = .failed(query: key, failure)
        }
    }

    private func remember(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
        while recency.count > Self.memoryLimit {
            results[recency.removeFirst()] = nil
        }
    }

    @concurrent
    private nonisolated static func fetch(
        _ query: String, limit: Int, from provider: any WebSearchProvider
    ) async -> Result<[WebSearchResult], WebSearchFailure> {
        await Signposts.interval("WebSearch.fetch") {
            do throws(WebSearchFailure) {
                return .success(try await provider.search(query, limit: limit))
            } catch {
                return .failure(error)
            }
        }
    }
}
