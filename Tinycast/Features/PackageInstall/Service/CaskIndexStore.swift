import Foundation

/// Homebrew's cask install counts, cached on disk and refreshed daily, as `CurrencyRateStore` is.
@MainActor
@Observable
final class CaskIndexStore {
    struct Schedule: Sendable {
        /// Measured from the index's `fetchedAt`, so a relaunch never re-fetches a fresh index.
        let refresh: TimeInterval
        /// Shorter, so a Mac offline at launch picks the index up soon after it reconnects.
        let retry: TimeInterval

        static let standard = Schedule(refresh: 24 * 3600, retry: 30 * 60)
    }

    private nonisolated static let analyticsPath = "analytics/cask-install/homebrew-cask/30d.json"

    /// Kept while a refresh runs, so the card never drops back to loading.
    private(set) var index: CaskIndex?
    /// True while the cache is read or a fetch runs; with no index it means loading, not unavailable.
    private(set) var isFetching = false
    /// Bumped on every new index, for a reader's memo key.
    private(set) var revision = 0

    private let cacheURL: URL
    private let analyticsURL: URL
    private let session: URLSession
    private let schedule: Schedule
    private let now: () -> Date
    @ObservationIgnored private var pump: Task<Void, Never>?
    /// Bumped by `stop`, so a task that outlived it can never write state again.
    @ObservationIgnored private var generation = 0

    /// `baseURL` and `protocolClasses` exist so a harness can serve fixtures in process.
    init(
        cacheURL: URL, baseURL: URL = CaskAPI.base, protocolClasses: [AnyClass]? = nil,
        schedule: Schedule = .standard, now: @escaping () -> Date = Date.init
    ) {
        self.cacheURL = cacheURL
        analyticsURL = baseURL.appending(path: Self.analyticsPath)
        self.schedule = schedule
        self.now = now
        session = CaskAPI.session(protocolClasses: protocolClasses)
    }

    /// The cache is read here, off the main actor, rather than in `init` on the launch path.
    func start() {
        stop()
        let generation = generation
        isFetching = true
        pump = Task { [weak self] in
            await self?.loadCache(generation)
            while !Task.isCancelled, let self, self.generation == generation {
                // Clamped, so an index stamped in the future can't park the loop past one interval.
                let age = max(0, index.map { now().timeIntervalSince($0.fetchedAt) } ?? .infinity)
                guard age >= schedule.refresh else {
                    isFetching = false
                    try? await Task.sleep(for: .seconds(schedule.refresh - age))
                    continue
                }
                let fetched = await fetchAndStore(generation)
                try? await Task.sleep(for: .seconds(fetched ? schedule.refresh : schedule.retry))
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        generation += 1
        isFetching = false
    }

    private func loadCache(_ generation: Int) async {
        guard index == nil, let cached = await Self.readCache(cacheURL),
            self.generation == generation
        else { return }
        apply(cached)
    }

    private func fetchAndStore(_ generation: Int) async -> Bool {
        isFetching = true
        let result = await Self.fetch(analyticsURL, session: session, now: now())
        guard self.generation == generation, !Task.isCancelled else { return false }
        isFetching = false
        guard let result else { return false }
        apply(result.index)
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? result.cache.write(to: cacheURL, options: .atomic)
        return true
    }

    private func apply(_ index: CaskIndex) {
        self.index = index
        revision += 1
    }

    @concurrent
    private nonisolated static func readCache(_ url: URL) async -> CaskIndex? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CaskIndex.self, from: data)
    }

    /// Decoding and encoding stay off the main actor too; only plain values cross back.
    @concurrent
    private nonisolated static func fetch(_ url: URL, session: URLSession, now: Date) async
        -> (index: CaskIndex, cache: Data)?
    {
        let request = URLRequest(url: url, timeoutInterval: 20)
        guard let (data, response) = try? await session.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let index = try? CaskIndex.decode(analytics: data, now: now),
            let cache = try? JSONEncoder().encode(index)
        else { return nil }
        return (index, cache)
    }
}
