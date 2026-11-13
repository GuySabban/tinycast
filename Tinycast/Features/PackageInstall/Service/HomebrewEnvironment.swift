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
    nonisolated static func installedCasks(prefix: URL = prefix) async -> Set<String> {
        let caskroom = prefix.appending(path: "Caskroom")
        guard let tokens = try? FileManager.default.contentsOfDirectory(atPath: caskroom.path) else {
            return []
        }
        return Set(tokens.filter { token in
            CaskToken.isValid(token)
                && FileManager.default.fileExists(
                    atPath: caskroom.appending(path: "\(token)/.metadata").path(percentEncoded: false))
        })
    }
}
