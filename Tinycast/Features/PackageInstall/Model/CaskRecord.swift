import Foundation

/// The part of one cask's API record the approval flow reads, for this Mac's macOS release.
struct CaskRecord: Sendable, Equatable {
    struct AppArtifact: Sendable, Equatable {
        let source: String
        /// Already resolved by Homebrew, such as `/Applications/Blender.app`.
        let target: String

        /// What the installed app is found by; a renaming target differs from `source`.
        var installedName: String {
            target.split(separator: "/").last.map(String.init) ?? target
        }

        /// Homebrew writes a target under the home folder as `/$HOME/…`.
        func path(home: String) -> String {
            for marker in ["/$HOME/", "$HOME/", "~/"] where target.hasPrefix(marker) {
                return home + "/" + target.dropFirst(marker.count)
            }
            return target
        }
    }

    /// Why Homebrew disabled or deprecated a cask.
    struct Retirement: Sendable, Equatable {
        enum Reason: Sendable, Equatable {
            case discontinued
            case noLongerAvailable
            case noLongerMeetsCriteria
            case unmaintained
            case unreachable
            case failsGatekeeperCheck
            case movedToMacAppStore
            /// A sentence the cask states in place of one of Homebrew's symbols.
            case stated(String)

            /// Homebrew's own wording for each symbol, so the dialog never shows a raw one.
            var sentence: String {
                switch self {
                case .discontinued: String(localized: "It is discontinued upstream.")
                case .noLongerAvailable: String(localized: "It is no longer available upstream.")
                case .noLongerMeetsCriteria:
                    String(localized: "It no longer meets Homebrew's criteria for casks.")
                case .unmaintained: String(localized: "It is not maintained upstream.")
                case .unreachable: String(localized: "Its download can no longer be reached.")
                case .failsGatekeeperCheck:
                    String(localized: "It does not pass the macOS Gatekeeper check.")
                case .movedToMacAppStore:
                    String(localized: "It is now only distributed on the Mac App Store.")
                case .stated(let words): String(localized: "Homebrew says it \(words).")
                }
            }

            init(_ raw: String) {
                self =
                    switch raw {
                    case "discontinued": .discontinued
                    case "no_longer_available": .noLongerAvailable
                    case "no_longer_meets_criteria": .noLongerMeetsCriteria
                    case "unmaintained": .unmaintained
                    case "unreachable": .unreachable
                    case "fails_gatekeeper_check": .failsGatekeeperCheck
                    case "moved_to_mas": .movedToMacAppStore
                    default: .stated(raw)
                    }
            }
        }

        let reason: Reason?
        let date: String?
        let replacementCask: String?
    }

    enum Malformed: Error, Equatable {
        case notAnObject
        case missingField(String)
        case invalidToken
        case appWithoutTarget
    }

    let token: String
    let names: [String]
    let summary: String?
    let homepage: URL?
    let downloadURL: URL?
    let version: String
    let apps: [AppArtifact]
    /// A pkg, a step marked sudo, or a target in a system folder: `HOMEBREW_NO_SUDO` would stop it.
    let needsPassword: Bool
    /// Homebrew only stages an installer the user must open, so an in-app install proves nothing.
    let hasManualInstaller: Bool
    let disabled: Retirement?
    let deprecated: Retirement?

    var displayName: String { names.first ?? token }

    /// Nil for `latest`; Homebrew's build suffix after a comma is dropped.
    var displayVersion: String? {
        version == "latest" ? nil : String(version.prefix { $0 != "," })
    }

    /// Homebrew's release names, for the releases this app runs on.
    private static let releaseNames = [26: "tahoe", 27: "golden_gate"]

    /// The key of this Mac's entry in `variations`; Apple silicon only, as is the feature.
    static func variation(macOSMajorVersion: Int) -> String? {
        releaseNames[macOSMajorVersion].map { "arm64_\($0)" }
    }

    /// `variation` overlays that release's entry on the base record, which is the newest release's.
    static func decode(_ data: Data, variation: String?) throws(Malformed) -> CaskRecord {
        guard var fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .notAnObject
        }
        if let variation, let variations = fields["variations"] as? [String: Any],
            let overrides = variations[variation] as? [String: Any]
        {
            fields.merge(overrides) { _, override in override }
        }
        guard let token = fields["token"] as? String else { throw .missingField("token") }
        guard CaskToken.isValid(token) else { throw .invalidToken }
        guard let version = fields["version"] as? String else { throw .missingField("version") }
        guard let artifacts = fields["artifacts"] as? [[String: Any]] else {
            throw .missingField("artifacts")
        }
        return CaskRecord(
            token: token,
            names: fields["name"] as? [String] ?? [],
            summary: fields["desc"] as? String,
            homepage: (fields["homepage"] as? String).flatMap { URL(string: $0) },
            downloadURL: (fields["url"] as? String).flatMap { URL(string: $0) },
            version: version,
            apps: try apps(in: artifacts),
            needsPassword: needsPassword(artifacts),
            hasManualInstaller: hasManualInstaller(artifacts),
            disabled: retirement(fields, flag: "disabled", prefix: "disable"),
            deprecated: retirement(fields, flag: "deprecated", prefix: "deprecation"))
    }

    private static func apps(in artifacts: [[String: Any]]) throws(Malformed) -> [AppArtifact] {
        var apps: [AppArtifact] = []
        for artifact in artifacts {
            guard let source = (artifact["app"] as? [Any])?.first as? String else { continue }
            guard let target = artifact["target"] as? String else { throw .appWithoutTarget }
            apps.append(AppArtifact(source: source, target: target))
        }
        return apps
    }

    /// Run only by `brew uninstall`, so a sudo inside them never stops an install.
    private static let uninstallKinds: Set<String> = [
        "uninstall", "zap", "uninstall_preflight_steps", "uninstall_postflight_steps"
    ]
    private static let systemFolders = ["/Library/", "/usr/", "/System/"]

    private static func needsPassword(_ artifacts: [[String: Any]]) -> Bool {
        artifacts.contains { artifact in
            if artifact["pkg"] != nil { return true }
            if let target = artifact["target"] as? String,
                systemFolders.contains(where: target.hasPrefix)
            {
                return true
            }
            return artifact.contains { kind, value in
                !uninstallKinds.contains(kind) && asksForSudo(value)
            }
        }
    }

    /// `sudo` is `true`, or a condition such as `"if_needed"` that may still need the password.
    private static func asksForSudo(_ value: Any) -> Bool {
        if let object = value as? [String: Any] {
            if let sudo = object["sudo"], (sudo as? Bool) ?? (sudo is String) { return true }
            return object.values.contains(where: asksForSudo)
        }
        if let array = value as? [Any] { return array.contains(where: asksForSudo) }
        return false
    }

    private static func hasManualInstaller(_ artifacts: [[String: Any]]) -> Bool {
        artifacts.contains { artifact in
            (artifact["installer"] as? [Any])?.contains { ($0 as? [String: Any])?["manual"] != nil }
                ?? false
        }
    }

    private static func retirement(_ fields: [String: Any], flag: String, prefix: String)
        -> Retirement?
    {
        guard fields[flag] as? Bool == true else { return nil }
        return Retirement(
            reason: (fields["\(prefix)_reason"] as? String).map(Retirement.Reason.init),
            date: fields["\(prefix)_date"] as? String,
            replacementCask: fields["\(prefix)_replacement_cask"] as? String)
    }
}
