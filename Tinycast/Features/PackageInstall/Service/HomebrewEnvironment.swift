import Foundation

/// Where Homebrew lives and what it has installed, read from disk without running `brew`.
enum HomebrewEnvironment {
    /// Apple silicon only, as the feature is; `ExecutableLocator` would start a login shell.
    nonisolated static let prefix = URL(fileURLWithPath: "/opt/homebrew")

    nonisolated static func brew(prefix: URL = prefix) -> URL? {
        let brew = prefix.appending(path: "bin/brew")
        return FileManager.default.isExecutableFile(atPath: brew.path(percentEncoded: false)) ? brew : nil
    }

    /// Skips a folder an interrupted install left behind, as `brew install` itself does.
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
            guard hasInstallRecord(metadata: metadata, token: token) else { continue }
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

    /// Homebrew's test: the newest `.metadata/VERSION/TIMESTAMP` holds `Casks/TOKEN.json`.
    nonisolated static func hasInstallRecord(metadata: URL, token: String) -> Bool {
        let stamps = visibleChildren(of: metadata).flatMap { version in
            visibleChildren(of: metadata.appending(path: version))
                .map { metadata.appending(path: "\(version)/\($0)") }
        }
        guard let newest = stamps.max(by: { $0.lastPathComponent < $1.lastPathComponent }) else {
            return false
        }
        return ["json", "rb"].contains { kind in
            let caskfile = newest.appending(path: "Casks/\(token).\(kind)")
            return FileManager.default.fileExists(atPath: caskfile.path(percentEncoded: false))
        }
    }

    private nonisolated static func visibleChildren(of folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [])
            .filter { !$0.hasPrefix(".") }
    }
}
