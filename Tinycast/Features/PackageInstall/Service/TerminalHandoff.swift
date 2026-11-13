import AppKit

/// Runs one `brew` command where the user can see and answer it: a password, or a manual step.
@MainActor
enum TerminalHandoff {
    /// Named rather than the `.command` default, which a user may have pointed at another terminal.
    static let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

    /// A `.command` file opened in Terminal needs no Automation grant; the script deletes itself.
    static func run(_ invocation: BrewInvocation) async throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "install-\(invocation.token)-\(UUID().uuidString).command")
        guard
            FileManager.default.createFile(
                atPath: file.path(percentEncoded: false), contents: Data(invocation.terminalScript.utf8),
                attributes: [.posixPermissions: 0o700])
        else { throw CocoaError(.fileWriteUnknown) }
        do {
            try await NSWorkspace.shared.open(
                [file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    /// For Homebrew's own setup command, which the user pastes and runs there.
    static func openTerminal() {
        AppLauncher.launch(terminal)
    }
}
