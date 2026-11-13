import Foundation

/// One cask Homebrew's Caskroom records, and the apps its install receipt says it placed.
struct InstalledCask: Sendable, Equatable {
    let token: String
    let appPaths: [String]
    /// Filled by the service that looked: recorded apps no longer on disk.
    let missingAppPaths: [String]

    var missingAppName: String? {
        missingAppPaths.first.map { $0.split(separator: "/").last.map(String.init) ?? $0 }
    }

    /// The receipt's `uninstall_artifacts` name each app; `config.json` says which folder it used.
    static func appPaths(receipt: Data, config: Data?, home: String) -> [String] {
        guard let receipt = (try? JSONSerialization.jsonObject(with: receipt)) as? [String: Any],
            let artifacts = receipt["uninstall_artifacts"] as? [[String: Any]]
        else { return [] }
        let folder = expanded(appFolder(config: config), home: home)
        return artifacts.compactMap { artifact in
            guard let app = artifact["app"] as? [Any], let source = app.first as? String else {
                return nil
            }
            let renamed = (app.dropFirst().first as? [String: Any])?["target"] as? String
            let target = renamed ?? String(source.split(separator: "/").last ?? Substring(source))
            if target.hasPrefix("/") || target.hasPrefix("~/") { return expanded(target, home: home) }
            return folder + "/" + target
        }
    }

    /// Homebrew layers an install's own `--appdir` over the environment's over its default.
    private static func appFolder(config: Data?) -> String {
        let layers = config.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        for layer in ["explicit", "env", "default"] {
            if let folder = (layers?[layer] as? [String: Any])?["appdir"] as? String { return folder }
        }
        return "/Applications"
    }

    private static func expanded(_ path: String, home: String) -> String {
        path.hasPrefix("~/") ? home + path.dropFirst() : path
    }
}
