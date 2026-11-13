import Foundation

/// Starts one approved install. The approval itself lives in the coordinator, never here.
enum CaskInstaller {
    /// The fixed script takes `brew` and the token as `$1` and `$2`, so the shell parses neither.
    nonisolated static func install(_ invocation: BrewInvocation) -> ShellCommandSession {
        ShellCommandRunner.stream(BrewInvocation.script, arguments: invocation.arguments)
    }
}
