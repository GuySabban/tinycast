import Foundation

/// One `brew install --cask`, as the dialog shows it and exactly as `CaskInstaller` runs it.
struct BrewInvocation: Sendable, Equatable {
    /// Fixed text: `$1` is `brew` and `$2` the token, so no outside text is parsed by the shell.
    static let script = """
        HOMEBREW_NO_SUDO=1 HOMEBREW_NO_ASK=1 HOMEBREW_CASK_OPTS= HOMEBREW_NO_ANALYTICS=1 \
        HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 exec "$1" install --cask "$2"
        """

    let brew: URL
    let token: String

    init?(brew: URL, token: String) {
        guard CaskToken.isValid(token) else { return nil }
        self.brew = brew
        self.token = token
    }

    var displayText: String { "brew install --cask \(token)" }

    /// The script's positional values, in order.
    var arguments: [String] { [brew.path(percentEncoded: false), token] }
}
