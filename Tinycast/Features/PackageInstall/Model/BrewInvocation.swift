import Foundation

/// One `brew` cask command, as the dialog shows it and exactly as it is run.
struct BrewInvocation: Sendable, Equatable {
    enum Verb: String, Sendable {
        case install
        case reinstall
    }

    /// Fixed text: `$1` is `brew`, `$2` the verb and `$3` the token, none parsed by the shell.
    static let script = """
        HOMEBREW_NO_SUDO=1 HOMEBREW_NO_ASK=1 HOMEBREW_CASK_OPTS= HOMEBREW_NO_ANALYTICS=1 \
        HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1 exec "$1" "$2" --cask "$3"
        """

    let brew: URL
    let token: String
    let verb: Verb

    init?(brew: URL, token: String, verb: Verb = .install) {
        guard CaskToken.isValid(token) else { return nil }
        self.brew = brew
        self.token = token
        self.verb = verb
    }

    var displayText: String { "brew \(verb.rawValue) --cask \(token)" }

    /// The script's positional values, in order.
    var arguments: [String] { [brew.path(percentEncoded: false), verb.rawValue, token] }

    /// A `.command` file's text; no `HOMEBREW_NO_SUDO`, since a visible terminal may ask.
    var terminalScript: String {
        """
        #!/bin/zsh
        rm -f -- "$0"
        print -r -- \(Self.quoted(displayText))
        HOMEBREW_NO_ANALYTICS=1 exec \(Self.quoted(arguments[0])) \(verb.rawValue) --cask \(Self.quoted(token))
        """
    }

    /// Homebrew's words when a step needs `sudo` and `HOMEBREW_NO_SUDO` forbids it.
    static func refusedSudo(in output: String) -> Bool {
        output.contains("sudo is disabled by HOMEBREW_NO_SUDO")
    }

    private static func quoted(_ text: String) -> String {
        "'" + text.replacing("'", with: #"'\''"#) + "'"
    }
}
