import Foundation

/// Where Homebrew lives and what it has installed, read from disk without running `brew`.
enum HomebrewEnvironment {
    /// Apple silicon only, as the feature is; `ExecutableLocator` would start a login shell.
    nonisolated static let prefix = URL(fileURLWithPath: "/opt/homebrew")

    nonisolated static func brew(prefix: URL = prefix) -> URL? {
        let brew = prefix.appending(path: "bin/brew")
        return FileManager.default.isExecutableFile(atPath: brew.path(percentEncoded: false)) ? brew : nil
    }

    /// Homebrew writes `.metadata` once an install completes, so a half-done folder is skipped.
    @concurrent
    nonisolated static func installedCasks(
        prefix: URL = prefix, home: String = NSHomeDirectory()
    ) async -> [String: InstalledCask] {
        let caskroom = prefix.appending(path: "Caskroom")
        guard let tokens = try? FileManager.default.contentsOfDirectory(atPath: caskroom.path(percentEncoded: false)) else {
            return [:]
        }
        var installed: [String: InstalledCask] = [:]
        for token in tokens where CaskToken.isValid(token) {
            let metadata = caskroom.appending(path: "\(token)/.metadata")
            guard FileManager.default.fileExists(atPath: metadata.path(percentEncoded: false)) else {
                continue
            }
            let paths = (try? Data(contentsOf: metadata.appending(path: "INSTALL_RECEIPT.json")))
                .map { receipt in
                    InstalledCask.appPaths(
                        receipt: receipt,
                        config: try? Data(contentsOf: metadata.appending(path: "config.json")),
                        home: home)
                } ?? []
            installed[token] = InstalledCask(
                token: token, appPaths: paths,
                missingAppPaths: paths.filter { !FileManager.default.fileExists(atPath: $0) })
        }
        return installed
    }
}
