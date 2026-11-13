import AppKit

/// The card's whole read path: a real store from a cache, a scratch Caskroom read by the real
/// `HomebrewEnvironment`, and `PackageInstallCoordinator.candidate(for:)` itself. Only the app's own
/// collaborators below are stand-ins, so nothing is fetched, installed, opened or shown.
@main
@MainActor
struct PackageInstallCoordinatorTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        if (try? condition()) == true {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expectSettles(_ message: String, within seconds: Double = 5, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition() {
            guard ContinuousClock.now < deadline else { return expect(false, message) }
            try? await Task.sleep(for: .milliseconds(10))
        }
        expect(true, message)
    }

    static let now = Date(timeIntervalSinceReferenceDate: 816_000_000)

    static func main() async throws {
        let fixture = try World()
        let coordinator = fixture.coordinator
        coordinator.applyEnabled()
        await expectSettles("the cached index and the Caskroom are both read") {
            fixture.store.index != nil && coordinator.installed.count == 3
        }

        // prowlarr is disabled, so the 30-day file has no row for it: the bug this harness exists for.
        expect(fixture.store.index?.contains(token: "prowlarr") == false, "the counts lack prowlarr")
        let prowlarr = coordinator.candidate(for: "install prowlarr")
        expect(token(of: prowlarr) == "prowlarr", "an installed cask the counts lack still leads the card")
        expect(prowlarr?.installation == .appMissing("Prowlarr.app"), "and the card says its app is missing")
        let wine = coordinator.candidate(for: "install wine-stable")
        expect(token(of: wine) == "wine-stable", "wine-stable is in the counts")
        expect(wine?.installation == .appMissing("Wine Stable.app"), "and its app is missing too")
        let obsidian = coordinator.candidate(for: "install obsidian")
        expect(obsidian?.installation == .installed, "an app still where Homebrew put it is installed")
        let blender = coordinator.candidate(for: "install blender")
        expect(token(of: blender) == "blender", "an ordinary match")
        expect(blender?.installation == nil, "with nothing the Caskroom says")

        expect(coordinator.candidate(for: "install b") == nil, "one letter is no request")
        expect(coordinator.candidate(for: "blender") == nil, "an ordinary query is no request")
        expect(coordinator.candidate(for: "install obsidian") == obsidian, "a repeat comes from the memo")

        // The card re-renders only if reading it registered the snapshot with Observation.
        let changed = Flag()
        withObservationTracking {
            _ = coordinator.candidate(for: "install obsidian")
        } onChange: {
            changed.set()
        }
        try FileManager.default.removeItem(at: fixture.apps.appending(path: "Obsidian.app"))
        coordinator.refreshInstalled()
        await expectSettles("a new snapshot reaches the card's reader") { changed.isSet }
        expect(
            coordinator.candidate(for: "install obsidian")?.installation == .appMissing("Obsidian.app"),
            "the memo yields to the new snapshot")

        coordinator.setEnabled(false)
        expect(coordinator.candidate(for: "install blender") == nil, "off means no card")
        expect(!fixture.store.isFetching, "and the store is stopped")
        expect(fixture.settings.isEnabled == false, "and the switch is saved")
        coordinator.setEnabled(true)
        await expectSettles("on again, the card comes back") {
            coordinator.candidate(for: "install blender") != nil
        }
        fixture.store.stop()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func token(of candidate: PackageCandidate?) -> String? {
        guard case .match(let entry, _)? = candidate?.state else { return nil }
        return entry.token
    }

    /// A scratch home, Caskroom and cache, laid out as on the owner's Mac on 2026-11-13.
    @MainActor
    struct World {
        let apps: URL
        let store: CaskIndexStore
        let settings: PackageInstallSettingsStore
        let coordinator: PackageInstallCoordinator

        init() throws {
            let root = FileManager.default.temporaryDirectory
                .appending(path: "PackageInstallCoordinatorTests-\(UUID().uuidString)")
            let prefix = root.appending(path: "homebrew")
            apps = root.appending(path: "Applications")
            let config = Data(#"{"default":{"appdir":"\#(apps.path)"},"env":{},"explicit":{}}"#.utf8)
            for (cask, app, present) in [
                ("prowlarr", "Prowlarr.app", false), ("wine-stable", "Wine Stable.app", false),
                ("obsidian", "Obsidian.app", true),
            ] {
                let metadata = prefix.appending(path: "Caskroom/\(cask)/.metadata")
                try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
                try Data(#"{"uninstall_artifacts":[{"app":["\#(app)"]}]}"#.utf8)
                    .write(to: metadata.appending(path: "INSTALL_RECEIPT.json"))
                try config.write(to: metadata.appending(path: "config.json"))
                if present {
                    try FileManager.default.createDirectory(
                        at: apps.appending(path: "\(app)/Contents"), withIntermediateDirectories: true)
                }
            }
            let counts = try Data(contentsOf: URL(fileURLWithPath: "Tests/package-fixtures/cask-install-30d.json"))
            let cache = root.appending(path: "cask-index.json")
            try JSONEncoder().encode(CaskIndex.decode(analytics: counts, now: PackageInstallCoordinatorTests.now))
                .write(to: cache)
            store = CaskIndexStore(
                cacheURL: cache, baseURL: URL(string: "https://unreachable.test/")!,
                now: { PackageInstallCoordinatorTests.now })
            settings = PackageInstallSettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            coordinator = PackageInstallCoordinator(
                settings: settings, index: store, appIndex: AppIndex(),
                paletteCoordinator: PaletteCoordinator(), settingsCoordinator: SettingsCoordinator(),
                activationPolicy: ActivationPolicy(), core: AppCore(), prefix: prefix, home: root.path)
        }
    }
}

/// Set from Observation's change callback, which may run on another thread.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

// MARK: - Stand-ins for the app's own collaborators

struct DialogAction {
    enum Role { case standard, destructive, cancel }
    let title: String
    var role: Role = .standard
}

enum DialogTone: Sendable { case neutral, success, danger }

@MainActor
final class AppCore {
    func showMessage(_ message: String, tone: DialogTone = .success) {}
    func showProgress(_ message: String, onCancel: (() -> Void)? = nil) {}
    func hideProgress() {}
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {}
    func confirm(
        title: String, message: String?, symbol: String?, confirmTitle: String,
        tone: DialogTone = .danger, confirmRole: DialogAction.Role = .destructive
    ) async -> Bool { false }
    func choose(
        title: String, message: String?, symbol: String?, options: [DialogAction], defaultIndex: Int
    ) async -> Int { options.count - 1 }
    func reportFailure(title: String, message: String, symbol: String, recovery: String?) async -> Bool {
        false
    }
}

struct AppEntry {
    enum Kind { case application }
    let kind: Kind
    let url: URL
}

@MainActor
final class AppIndex {
    var apps: [AppEntry] = []
    func refresh() async {}
}

@MainActor
final class PaletteCoordinator {
    var isVisible = false
    func hidePalette(restoreFocus: Bool = true) {}
}

enum SettingsTab { case applications }

@MainActor
final class SettingsCoordinator {
    func showSettings(tab: SettingsTab? = nil) {}
}

final class ActivationPolicy {}

struct CommandOutcome {
    let summary: String
    let hint: String?
    let succeeded: Bool
    let finishedAt: Date
}

@MainActor
final class CommandOutputPresenter {
    init(
        activation: ActivationPolicy, rerun: @escaping (UUID) -> Void, stop: @escaping (UUID) -> Void,
        openSettings: @escaping () -> Void
    ) {}
    func begin(commandID: UUID, name: String, commandText: String, symbol: String) -> UUID { UUID() }
    func append(_ text: String, to id: UUID) {}
    func finish(_ outcome: CommandOutcome, for id: UUID) {}
}

enum AppLauncher {
    static func launch(_ url: URL) {}
    static func open(_ url: URL) {}
}

enum Paster {
    static func copyPlainText(_ text: String) -> Bool { true }
}

@MainActor
enum TerminalHandoff {
    static func run(_ invocation: BrewInvocation) async throws {}
    static func openTerminal() {}
}
