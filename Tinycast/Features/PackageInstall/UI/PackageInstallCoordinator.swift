import AppKit

/// The install feature's action surface: the card's candidate, and the flow Return starts.
@MainActor
@Observable
final class PackageInstallCoordinator {
    let settings: PackageInstallSettingsStore
    /// Homebrew's Caskroom as last read; the card reads it, and every Return reads it afresh.
    private(set) var installed: [String: InstalledCask] = [:]
    private let index: CaskIndexStore
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let activationPolicy: ActivationPolicy
    /// Dialog and message-HUD presentation only — never for state this type owns.
    private unowned let core: AppCore
    @ObservationIgnored private let session = CaskAPI.session()
    /// One deep: the launcher builds its rows several times per keystroke.
    @ObservationIgnored private var memo: (key: MemoKey, candidate: PackageCandidate?)?
    @ObservationIgnored private var flow: Task<Void, Never>?
    /// Bumped by a new flow or a cancel, so a reply to an older one is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var liveRun: (id: UUID, token: String, stop: @Sendable () -> Void)?
    @ObservationIgnored private var lastRunToken: String?
    /// Built on first use; it shares the Command Output window's title and saved frame.
    @ObservationIgnored private lazy var output = CommandOutputPresenter(
        activation: activationPolicy,
        rerun: { [unowned self] _ in self.rerun() },
        stop: { [unowned self] in self.stopRun(id: $0) },
        openSettings: { [unowned self] in self.settingsCoordinator.showSettings(tab: .applications) })

    private struct MemoKey: Equatable {
        let query: String
        let revision: Int
        let isFetching: Bool
        let installed: [String: InstalledCask]
    }

    init(
        settings: PackageInstallSettingsStore, index: CaskIndexStore, appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator, settingsCoordinator: SettingsCoordinator,
        activationPolicy: ActivationPolicy, core: AppCore
    ) {
        self.settings = settings
        self.index = index
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.activationPolicy = activationPolicy
        self.core = core
    }

    // MARK: - Lifecycle

    func applyEnabled() {
        guard settings.isEnabled else {
            index.stop()
            cancel()
            return
        }
        index.start()
        refreshInstalled()
    }

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        applyEnabled()
    }

    /// Run on every launcher show, so the card's "installed" and "missing" stay current.
    func refreshInstalled() {
        guard settings.isEnabled else { return }
        Task { [weak self] in
            let installed = await HomebrewEnvironment.installedCasks()
            guard let self, self.settings.isEnabled, installed != self.installed else { return }
            self.installed = installed
        }
    }

    // MARK: - The card

    /// Read by `LauncherScreen.init`; memory only, so typing never touches disk or network.
    func candidate(for query: String) -> PackageCandidate? {
        guard settings.isEnabled, let name = InstallIntent.name(in: query) else { return nil }
        // Read before the memo, so Observation re-renders the card when any of them changes.
        let key = MemoKey(
            query: name, revision: index.revision, isFetching: index.isFetching, installed: installed)
        if let memo, memo.key == key { return memo.candidate }
        let candidate = Signposts.interval("PackageInstall.match") {
            PackageCandidate(
                requestedName: name, index: index.index, isFetchingIndex: index.isFetching,
                installed: installed)
        }
        memo = (key, candidate)
        return candidate
    }

    func activate(_ candidate: PackageCandidate) {
        guard case .match(let entry, _) = candidate.state else { return }
        install(token: entry.token)
    }

    /// Opens the approval for any token the index offered, the card's own or an alternate's.
    func install(token: String) {
        guard settings.isEnabled else { return }
        guard flow == nil else {
            core.showMessage(String(localized: "An install is already in progress."), tone: .neutral)
            return
        }
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        generation += 1
        let generation = generation
        flow = Task { [weak self] in
            await self?.run(token: token, generation: generation)
            if self?.generation == generation { self?.flow = nil }
        }
    }

    func copyInstallCommand(token: String) {
        copy("brew install --cask \(token)")
    }

    func openHomebrewPage(token: String) {
        guard CaskToken.isValid(token),
            let url = URL(string: "https://formulae.brew.sh/cask/\(token)")
        else { return }
        AppLauncher.open(url)
    }

    // MARK: - The flow

    /// Cancelling a lookup ends the flow silently; it is never reported as a failure.
    private func cancel() {
        guard flow != nil, liveRun == nil else { return }
        flow?.cancel()
        flow = nil
        generation += 1
        core.hideProgress()
    }

    private func run(token: String, generation: Int) async {
        core.showProgress(
            String(localized: "Looking up \(token) on Homebrew…"),
            onCancel: { [weak self] in self?.cancel() })
        let record: CaskRecord
        let facts: InstallPlan.Facts
        do {
            let present = Set(appIndex.apps.filter { $0.kind == .application }.map(\.url.lastPathComponent))
            (record, facts) = try await Self.lookUp(token, presentAppNames: present, session: session)
        } catch is CancellationError {
            return
        } catch {
            guard self.generation == generation else { return }
            core.hideProgress()
            await reportLookupFailure(error, token: token)
            return
        }
        guard self.generation == generation, !Task.isCancelled else { return }
        core.hideProgress()
        installed = facts.installedCasks
        await present(InstallPlan.make(record: record, facts: facts), record: record, generation: generation)
    }

    /// The record and the Caskroom are read together; the signpost spans Return to the dialog.
    @concurrent
    private nonisolated static func lookUp(
        _ token: String, presentAppNames: Set<String>, session: URLSession
    ) async throws -> (CaskRecord, InstallPlan.Facts) {
        try await Signposts.interval("PackageInstall.lookup") {
            let release = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            async let record = CaskAPI.record(
                token: token, variation: CaskRecord.variation(macOSMajorVersion: release), session: session)
            async let installed = HomebrewEnvironment.installedCasks()
            let facts = InstallPlan.Facts(
                brew: HomebrewEnvironment.brew(), installedCasks: await installed,
                presentAppNames: presentAppNames)
            return (try await record, facts)
        }
    }

    private func reportLookupFailure(_ error: any Error, token: String) async {
        let message =
            switch error as? CaskAPI.Failure {
            case .notFound: String(localized: "Homebrew has no cask named “\(token)” any more.")
            case .malformed: String(localized: "Homebrew sent a reply that could not be read.")
            case .unavailable, nil: String(localized: "Homebrew could not be reached. Check your connection.")
            }
        await core.showNotice(
            title: String(localized: "Couldn't look up \(token)"), message: message,
            symbol: "exclamationmark.triangle", tone: .danger)
    }

    private func present(_ plan: InstallPlan, record: CaskRecord, generation: Int) async {
        let name = record.displayName
        switch plan {
        case .install(let invocation):
            let choice = await core.choose(
                title: String(localized: "Install \(name)?"),
                message: InstallApproval.message(record: record, invocation: invocation),
                symbol: "shippingbox",
                options: [
                    DialogAction(title: String(localized: "Install")),
                    DialogAction(title: String(localized: "Open in Terminal")),
                    DialogAction(title: String(localized: "Cancel"), role: .cancel),
                ],
                defaultIndex: 0)
            guard self.generation == generation else { return }
            if choice == 0 { await runInstall(invocation, record: record, generation: generation) }
            if choice == 1 { await openInTerminal(invocation) }
        case .terminal(let invocation):
            let why =
                record.needsPassword
                ? String(localized: "\(name) needs your administrator password, which Terminal can ask for.")
                : [
                    String(localized: "\(name) comes with an installer you open yourself."),
                    String(localized: "Terminal shows where Homebrew put it."),
                ].joined(separator: " ")
            await offerTerminal(
                invocation, title: String(localized: "Install \(name) in Terminal?"), why: why,
                confirmTitle: String(localized: "Open in Terminal"), generation: generation)
        case .reinstall(let invocation, let missingApp):
            await offerTerminal(
                invocation, title: String(localized: "\(missingApp) is missing"),
                why: [
                    String(localized: "Homebrew lists \(record.token) as installed, but \(missingApp) is gone."),
                    String(localized: "Reinstalling puts it back."),
                ].joined(separator: " "),
                confirmTitle: String(localized: "Reinstall in Terminal"), generation: generation)
        case .homebrewMissing:
            await offerHomebrewSetup(generation: generation)
        case .alreadyInstalled(let appName, let byHomebrew):
            await offerOpen(name: name, appName: appName, byHomebrew: byHomebrew)
        case .disabled(let retirement):
            var lines = [retirement.reason?.sentence].compactMap(\.self)
            if let replacement = retirement.replacementCask {
                lines.append(String(localized: "Try “\(replacement)” instead."))
            }
            await core.showNotice(
                title: String(localized: "Homebrew has disabled \(name)"),
                message: lines.joined(separator: " "), symbol: "exclamationmark.triangle", tone: .danger)
        case .invalidToken:
            await core.showNotice(
                title: String(localized: "Couldn't install \(name)"),
                message: String(localized: "Its cask name is not one Homebrew accepts."),
                symbol: "exclamationmark.triangle", tone: .danger)
        }
    }

    private func offerTerminal(
        _ invocation: BrewInvocation, title: String, why: String, confirmTitle: String, generation: Int
    ) async {
        let choice = await core.choose(
            title: title,
            message: why + "\n\n" + String(localized: "Runs: \(invocation.displayText)"),
            symbol: "terminal",
            options: [
                DialogAction(title: confirmTitle),
                DialogAction(title: String(localized: "Copy Command")),
                DialogAction(title: String(localized: "Cancel"), role: .cancel),
            ],
            defaultIndex: 0)
        guard self.generation == generation else { return }
        if choice == 0 { await openInTerminal(invocation) }
        if choice == 1 { copy(invocation.displayText) }
    }

    private func offerHomebrewSetup(generation: Int) async {
        let choice = await core.choose(
            title: String(localized: "Homebrew is not installed"),
            message: [
                String(localized: "Installing apps from the launcher uses Homebrew."),
                String(localized: "Paste this command in Terminal to set it up, then try again:"),
            ].joined(separator: " ") + "\n\n" + InstallPlan.homebrewSetupCommand,
            symbol: "shippingbox",
            options: [
                DialogAction(title: String(localized: "Copy and Open Terminal")),
                DialogAction(title: String(localized: "Copy Command")),
                DialogAction(title: String(localized: "Cancel"), role: .cancel),
            ],
            defaultIndex: 0)
        guard self.generation == generation, choice < 2 else { return }
        copy(InstallPlan.homebrewSetupCommand)
        if choice == 0 { TerminalHandoff.openTerminal() }
    }

    private func offerOpen(name: String, appName: String?, byHomebrew: Bool) async {
        let detail =
            byHomebrew
            ? String(localized: "Homebrew installed it.")
            : String(localized: "It was installed without Homebrew, so the launcher leaves it alone.")
        guard let app = appName.flatMap(application(named:)) else {
            await core.showNotice(
                title: String(localized: "\(name) is already installed"), message: detail,
                symbol: "checkmark.circle", tone: .success)
            return
        }
        let open = await core.confirm(
            title: String(localized: "\(name) is already installed"), message: detail,
            symbol: "checkmark.circle", confirmTitle: String(localized: "Open"), tone: .neutral,
            confirmRole: .standard)
        if open { AppLauncher.launch(app.url) }
    }

    private func application(named fileName: String) -> AppEntry? {
        appIndex.apps.first { $0.kind == .application && $0.url.lastPathComponent == fileName }
    }

    private func openInTerminal(_ invocation: BrewInvocation) async {
        do {
            try await TerminalHandoff.run(invocation)
        } catch {
            let copyInstead = await core.reportFailure(
                title: String(localized: "Couldn't open Terminal"),
                message: String(localized: "Run this command in a terminal yourself: \(invocation.displayText)"),
                symbol: "terminal", recovery: String(localized: "Copy Command"))
            if copyInstead { copy(invocation.displayText) }
        }
    }

    private func copy(_ text: String) {
        guard Paster.copyPlainText(text) else { return }
        core.showMessage(String(localized: "Copied to the clipboard"))
    }

    // MARK: - Running brew

    private func runInstall(_ invocation: BrewInvocation, record: CaskRecord, generation: Int) async {
        let session = CaskInstaller.install(invocation)
        let runID = output.begin(
            commandID: UUID(), name: String(localized: "Install \(record.displayName)"),
            commandText: invocation.displayText, symbol: "shippingbox")
        liveRun = (runID, invocation.token, session.stop)
        lastRunToken = invocation.token
        defer { if liveRun?.id == runID { liveRun = nil } }
        // Kept short: only the sudo check reads it, and Homebrew states that near the end.
        var tail = ""
        for await event in session.events {
            switch event {
            case .output(let text):
                output.append(text, to: runID)
                tail = String((tail + text).suffix(8 * 1024))
            case .finished(let result):
                await finish(result, tail: tail, invocation: invocation, record: record, runID: runID)
            }
        }
        refreshInstalled()
        if BrewInvocation.refusedSudo(in: tail), self.generation == generation {
            await present(.terminal(invocation), record: record, generation: generation)
        }
    }

    private func finish(
        _ result: ShellCommandResult, tail: String, invocation: BrewInvocation, record: CaskRecord,
        runID: UUID
    ) async {
        switch result.termination {
        case .stopped:
            conclude(runID, String(localized: "Stopped. Homebrew may have left a partial download."), false)
        case .launchFailed:
            conclude(runID, String(localized: "The shell could not be started."), false)
        case .exited(let status) where status != 0:
            let summary =
                BrewInvocation.refusedSudo(in: tail)
                ? String(localized: "Homebrew needs your password for this cask.")
                : String(localized: "Homebrew exited with status \(status).")
            conclude(runID, summary, false)
        case .exited:
            let observation = await InstallVerifier.observe(record: record)
            switch InstallVerification.judge(observation) {
            case .verified:
                await appIndex.refresh()
                conclude(runID, String(localized: "Installed \(record.displayName)."), true)
                core.showMessage(String(localized: "\(record.displayName) is installed"))
            case .noCaskroomEntry:
                conclude(runID, String(localized: "Homebrew finished, but has no record of \(record.token)."), false)
            case .appMissing(let app):
                conclude(runID, String(localized: "Homebrew finished, but \(app) is not where the cask puts it."), false)
            case .appUntrusted(let app):
                let warning = [
                    String(localized: "\(app) is not signed by Apple or an identified developer."),
                    String(localized: "Check it before opening it."),
                ]
                conclude(runID, warning.joined(separator: " "), false)
            }
        }
    }

    private func conclude(_ runID: UUID, _ summary: String, _ succeeded: Bool) {
        output.finish(
            CommandOutcome(summary: summary, hint: nil, succeeded: succeeded, finishedAt: Date()), for: runID)
    }

    /// Run Again starts over from the lookup, approval included, never straight at `brew`.
    private func rerun() {
        guard let token = lastRunToken else { return }
        install(token: token)
    }

    private func stopRun(id: UUID) {
        guard let liveRun, liveRun.id == id else { return }
        liveRun.stop()
    }
}
