import Foundation

/// The switch under its own raw key, outside backups and `settings.json` (decision D6).
@MainActor
@Observable
final class PackageInstallSettingsStore {
    private static let enabledKey = "packageInstallEnabled"

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }
}
