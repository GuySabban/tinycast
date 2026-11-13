import Foundation

/// What approval offers for one cask on this Mac, decided before anything runs.
enum InstallPlan: Sendable, Equatable {
    struct Facts: Sendable, Equatable {
        /// Nil unless an executable sits at `/opt/homebrew/bin/brew`.
        let brew: URL?
        /// What Homebrew's Caskroom records, by token.
        let installedCasks: [String: InstalledCask]
        /// File names of the apps `AppIndex` holds, such as `Blender.app`.
        let presentAppNames: Set<String>
    }

    /// Exactly as brew.sh prints it; shown to copy, never run by the app.
    static let homebrewSetupCommand =
        #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    case install(BrewInvocation)
    /// A password or a manual installer step needs a terminal the user can see and answer.
    case terminal(BrewInvocation)
    case homebrewMissing
    /// Homebrew lists the cask, but its app is gone: `brew reinstall`, run in Terminal.
    case reinstall(BrewInvocation, missingApp: String)
    /// `appName` is the bundle to open; nil for a pkg.
    case alreadyInstalled(appName: String?, byHomebrew: Bool)
    case disabled(CaskRecord.Retirement)
    case invalidToken

    static func make(record: CaskRecord, facts: Facts) -> InstallPlan {
        if let retirement = record.disabled { return .disabled(retirement) }
        let presentApp = record.apps.map(\.installedName).first(where: facts.presentAppNames.contains)
        if let installed = facts.installedCasks[record.token] {
            guard let missing = installed.missingAppName, presentApp == nil else {
                return .alreadyInstalled(appName: presentApp, byHomebrew: true)
            }
            guard let brew = facts.brew else { return .homebrewMissing }
            guard let invocation = BrewInvocation(brew: brew, token: record.token, verb: .reinstall) else {
                return .invalidToken
            }
            return .reinstall(invocation, missingApp: missing)
        }
        if let presentApp { return .alreadyInstalled(appName: presentApp, byHomebrew: false) }
        guard let brew = facts.brew else { return .homebrewMissing }
        guard let invocation = BrewInvocation(brew: brew, token: record.token) else {
            return .invalidToken
        }
        return record.needsPassword || record.hasManualInstaller
            ? .terminal(invocation) : .install(invocation)
    }
}
