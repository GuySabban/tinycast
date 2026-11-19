import Foundation

/// The web results' action surface: the trigger, the launcher's rows, and where a row's Return goes.
@MainActor
final class WebSearchCoordinator {
    static let resultLimit = 5

    let settings: WebSearchSettingsStore
    private let session: WebSearchSession
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    /// Message-HUD presentation only — never for state this type owns.
    private unowned let core: AppCore
    private let openURL: @MainActor (URL) -> Void
    private let copyText: @MainActor (String) -> Bool

    init(
        settings: WebSearchSettingsStore, session: WebSearchSession, paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator, core: AppCore,
        openURL: @escaping @MainActor (URL) -> Void = { AppLauncher.open($0) },
        copyText: @escaping @MainActor (String) -> Bool = { Paster.copyPlainText($0) }
    ) {
        self.settings = settings
        self.session = session
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.core = core
        self.openURL = openURL
        self.copyText = copyText
        settings.onKeyRemoved = { [weak session] in session?.forget() }
    }

    /// A key read on each search, never while building rows; a missing key skips the Keychain.
    static func provider(
        for settings: WebSearchSettingsStore, baseURL: URL = ExaSearchProvider.base,
        protocolClasses: [AnyClass]? = nil
    ) -> WebSearchSession.ProviderSource {
        { [weak settings] in
            guard let settings, settings.keyStatus != .missing,
                let key = try? settings.key(), !key.isEmpty
            else { return nil }
            return ExaSearchProvider(key: key, baseURL: baseURL, protocolClasses: protocolClasses)
        }
    }

    var isAvailable: Bool { settings.isEnabled && settings.hasKey }

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        if !enabled { session.cancel() }
    }

    // MARK: - Trigger

    /// Leaves the panel open: the rows fill in under the query that asked for them.
    func search(_ query: String) {
        guard settings.isEnabled else { return }
        session.search(query)
    }

    func searchAgain(_ query: String) {
        guard settings.isEnabled else { return }
        session.search(query, again: true)
    }

    // MARK: - Rows

    /// Read by `LauncherScreen.init`; touches memory only, so typing never sends a request.
    func launcherRows(for query: String) -> [WebSearchRow] {
        guard settings.isEnabled else { return [] }
        let key = WebSearchSession.key(for: query)
        guard !key.isEmpty else { return [] }
        switch session.state {
        case .searching(let searched) where searched == key:
            return WebSearchRow.placeholders(count: Self.resultLimit)
        case .failed(let searched, let failure) where searched == key:
            return [.failure(failure)]
        default:
            return session.results(for: key)?.prefix(Self.resultLimit).map(WebSearchRow.result) ?? []
        }
    }

    /// A result opens its link; a failure retries, or opens Settings when only a new key can help.
    func open(_ row: WebSearchRow) {
        switch row {
        case .placeholder:
            return
        case .result(let result):
            guard let url = WebSearchResult.webLink(result.url.absoluteString) else { return }
            paletteCoordinator.hidePalette(restoreFocus: false)
            openURL(url)
        case .failure(let failure):
            if Self.needsSettings(failure) {
                showSettings()
            } else if case .failed(let query, _) = session.state {
                session.search(query, again: true)
            }
        }
    }

    func copyLink(_ result: WebSearchResult) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        guard copyText(result.url.absoluteString) else { return }
        core.showMessage(String(localized: "Link copied"))
    }

    func showSettings() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        settingsCoordinator.showSettings(tab: .fallbacks)
    }

    nonisolated static func needsSettings(_ failure: WebSearchFailure) -> Bool {
        failure == .missingKey || failure == .unauthorized
    }
}
