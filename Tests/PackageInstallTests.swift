import Foundation

/// Fixtures in `Tests/package-fixtures/` are Homebrew's API replies as served on 2026-11-13.
@main
@MainActor
struct PackageInstallTests {
    static var failures = 0
    static var passes = 0

    /// A condition that throws fails, so a decode error is reported where it happened.
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        if (try? condition()) == true {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() throws {
        recognisesInstallRequests()
        waitsForTwoLetters()
        validatesTokens()
        try decodesTheInstallCountFile()
        refusesMalformedInstallCounts()
        try survivesItsOwnCache()
        try matchesFiftyCommonNames()
        try ordersMatches()
        try resolvesCandidates()
        try decodesTheAppCask()
        try decodesThePkgCask()
        try decodesTheDisabledCask()
        try appliesTheVariationForThisMac()
        try decidesWhenAnInstallNeedsAPassword()
        refusesMalformedRecords()
        try shapesTheVersion()
        buildsOnlySafeInvocations()
        writesTheTerminalScript()
        recognisesARefusedSudo()
        try resolvesTargetsUnderHome()
        try plansEveryOutcome()
        readsInstallReceipts()
        try writesTheApproval()
        namesEveryRetirementReason()
        judgesEveryVerification()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: "Tests/package-fixtures/\(name).json"))
    }

    static let fetchedAt = Date(timeIntervalSinceReferenceDate: 816_000_000)

    static func index() throws -> CaskIndex {
        try CaskIndex.decode(analytics: fixture("cask-install-30d"), now: fetchedAt)
    }

    // MARK: Intent

    static func recognisesInstallRequests() {
        expect(InstallIntent.name(in: "install blender") == "blender", "the name follows the keyword")
        expect(InstallIntent.name(in: "Install Blender") == "Blender", "any case, name kept as typed")
        expect(InstallIntent.name(in: "INSTALL vlc") == "vlc", "an all-caps keyword")
        expect(
            InstallIntent.name(in: "  install   visual studio code  ") == "visual studio code",
            "outer space trimmed, inner words kept")
        expect(InstallIntent.name(in: "install\tzed") == "zed", "a tab separates like a space")
        expect(InstallIntent.name(in: "install") == nil, "the keyword alone asks for nothing yet")
        expect(InstallIntent.name(in: "install   ") == nil, "a keyword and spaces ask for nothing")
        expect(InstallIntent.name(in: "installer") == nil, "a longer word is not the keyword")
        expect(InstallIntent.name(in: "installblender") == nil, "the keyword needs a gap")
        expect(InstallIntent.name(in: "blender") == nil, "an ordinary query")
        expect(InstallIntent.name(in: "how to install blender") == nil, "the keyword must lead")
        expect(InstallIntent.name(in: "") == nil, "an empty query")
    }

    /// One letter matches hundreds of casks, so no card shows until a second is typed.
    static func waitsForTwoLetters() {
        expect(InstallIntent.minimumLetters == 2, "two letters before a match")
        expect(InstallIntent.name(in: "install b") == nil, "one letter shows no match")
        expect(InstallIntent.name(in: "install 1") == nil, "one digit shows no match")
        expect(InstallIntent.name(in: "install b-") == nil, "a separator is not a letter")
        expect(InstallIntent.name(in: "install b .") == nil, "nor is punctuation after a space")
        expect(InstallIntent.name(in: "install é") == nil, "one accented letter is still one")
        expect(InstallIntent.name(in: "install bl") == "bl", "two letters match")
        expect(InstallIntent.name(in: "install 1p") == "1p", "a digit counts as a letter")
        expect(InstallIntent.name(in: "install b l") == "b l", "two letters across words")
        expect(InstallIntent.name(in: "install 微信") == "微信", "two letters in another script")
    }

    static func validatesTokens() {
        for token in ["blender", "1password", "visual-studio-code", "google-chrome@beta", "notepad++",
            "font-fira_code", "dotnet-sdk8.0"]
        {
            expect(CaskToken.isValid(token), "\(token) is a valid token")
        }
        for token in ["", "-rf", ".hidden", "@beta", "Blender", "two words", "a;rm", "a/b", "$(x)", "a\nb",
            "café", "`x`", "a'b", "a\"b", "*"]
        {
            expect(!CaskToken.isValid(token), "\(token.debugDescription) is refused")
        }
    }

    // MARK: Index

    static func decodesTheInstallCountFile() throws {
        let index = try index()
        expect(index.entries.count == 6_043, "every token in the file is read")
        expect(index.fetchedAt == fetchedAt, "stamped with the injected clock")
        let blender = index.entries.first { $0.token == "blender" }
        expect(blender?.installs == 35_723, "a count with a thousands comma is read whole")
        let small = index.entries.first { $0.token == "010-editor" }
        expect(small?.installs == 45, "a count with no comma")
        let installs = index.entries.map(\.installs)
        expect(installs == installs.sorted(by: >), "entries run from most to least installed")
        expect(index.entries.first?.token == "codex", "the most installed cask leads")
    }

    static func refusesMalformedInstallCounts() {
        let badToken = #""Bad Token":[{"cask":"Bad Token","count":"5"}]"#
        let replies: [(String, String)] = [
            ("an HTML error page", "<html><body>502</body></html>"),
            ("an empty object", "{}"),
            ("another analytics category", #"{"category":"install","formulae":{"wget":[{"formula":"wget","count":"1"}]}}"#),
            ("no entries", #"{"category":"cask_install","formulae":{}}"#),
            ("only unusable entries", #"{"category":"cask_install","formulae":{\#(badToken),"ok":[{"count":"lots"}]}}"#),
        ]
        for (label, body) in replies {
            expect(
                (try? CaskIndex.decode(analytics: Data(body.utf8), now: fetchedAt)) == nil,
                "\(label) is refused")
        }
        let mixed = #"{"category":"cask_install","formulae":{\#(badToken),"good":[{"count":"1,204"}]}}"#
        let index = try? CaskIndex.decode(analytics: Data(mixed.utf8), now: fetchedAt)
        expect(
            index?.entries == [CaskIndex.Entry(token: "good", installs: 1_204)],
            "one unusable entry is dropped and the rest kept")
    }

    static func survivesItsOwnCache() throws {
        let index = try index()
        let data = try JSONEncoder().encode(index)
        let restored = try JSONDecoder().decode(CaskIndex.self, from: data)
        expect(restored == index, "the cached index decodes to the same index")
        expect(restored.matches("blender", limit: 1).first?.token == "blender", "a restored index matches")
        let source = try fixture("cask-install-30d").count
        expect(data.count < source, "the cache (\(data.count) B) is smaller than its source (\(source) B)")
    }

    /// Names people type, and the cask they mean. Misses are measured, not hidden (decision D4).
    static let commonNames: [(name: String, token: String)] = [
        ("blender", "blender"), ("firefox", "firefox"), ("chrome", "google-chrome"),
        ("google chrome", "google-chrome"), ("vscode", "visual-studio-code"),
        ("visual studio code", "visual-studio-code"), ("slack", "slack"), ("discord", "discord"),
        ("spotify", "spotify"), ("zoom", "zoom"), ("iterm", "iterm2"), ("docker", "docker-desktop"),
        ("obsidian", "obsidian"), ("notion", "notion"), ("vlc", "vlc"), ("rectangle", "rectangle"),
        ("raycast", "raycast"), ("1password", "1password"), ("telegram", "telegram"),
        ("whatsapp", "whatsapp"), ("figma", "figma"), ("postman", "postman"), ("arc", "arc"),
        ("brave", "brave-browser"), ("android studio", "android-studio"), ("intellij", "intellij-idea"),
        ("sublime text", "sublime-text"), ("teams", "microsoft-teams"), ("word", "microsoft-word"),
        ("excel", "microsoft-excel"), ("powerpoint", "microsoft-powerpoint"),
        ("github desktop", "github"), ("gimp", "gimp"), ("inkscape", "inkscape"),
        ("audacity", "audacity"), ("obs", "obs"), ("handbrake", "handbrake-app"),
        ("the unarchiver", "the-unarchiver"), ("signal", "signal"), ("tor browser", "tor-browser"),
        ("chatgpt", "chatgpt"), ("claude", "claude"), ("cursor", "cursor"), ("warp", "warp"),
        ("ghostty", "ghostty"), ("libreoffice", "libreoffice"), ("google drive", "google-drive"),
        ("zed", "zed"), ("karabiner", "karabiner-elements"), ("orbstack", "orbstack"),
    ]

    /// Display names the token does not carry; the full catalogue would find them (Phase 4).
    static let knownMisses: Set<String> = ["github desktop"]

    static func matchesFiftyCommonNames() throws {
        let index = try index()
        expect(commonNames.count == 50, "the list holds fifty names")
        var hits = 0
        for (name, token) in commonNames {
            let found = index.matches(name, limit: 5).map(\.token)
            if knownMisses.contains(name) {
                expect(found.first != token, "\(name) is still a known miss; move it to the hits")
                continue
            }
            expect(found.first == token, "\(name) → \(token), got \(found)")
            if found.first == token { hits += 1 }
        }
        expect(hits == commonNames.count - knownMisses.count, "\(hits) of \(commonNames.count) names hit")
    }

    static func ordersMatches() throws {
        let entries = [
            CaskIndex.Entry(token: "chrome-remote-desktop-host", installs: 300),
            CaskIndex.Entry(token: "google-chrome", installs: 20_000),
            CaskIndex.Entry(token: "google-chrome@beta", installs: 400),
            CaskIndex.Entry(token: "chromium", installs: 900),
            CaskIndex.Entry(token: "arc", installs: 1_000),
            CaskIndex.Entry(token: "arcade-maker", installs: 50_000),
        ]
        let small = CaskIndex(entries: entries, fetchedAt: fetchedAt)
        expect(small.entries.first?.token == "arcade-maker", "init orders by installs")
        expect(small.matches("arc", limit: 3).first?.token == "arc", "an exact token beats a bigger one")
        expect(
            small.matches("chrome", limit: 5).map(\.token)
                == ["google-chrome", "chrome-remote-desktop-host", "google-chrome@beta"],
            "whole words of the token come first, by installs, then partial hits")
        expect(small.matches("Google Chrome", limit: 1).first?.token == "google-chrome", "words join with a dash")
        expect(small.matches("chrome", limit: 1).count == 1, "the limit holds")
        expect(small.matches("chrome", limit: 0).isEmpty, "a zero limit asks for nothing")
        expect(small.matches("", limit: 5).isEmpty, "an empty name matches nothing")
        expect(small.matches("   ", limit: 5).isEmpty, "a blank name matches nothing")
        expect(small.matches("qqqq", limit: 5).isEmpty, "a name nothing contains")

        let index = try index()
        expect(index.matches("xqzjv", limit: 5).isEmpty, "no stray hit across the whole file")
        let vscode = index.matches("vscode", limit: 5).map(\.token)
        expect(vscode.first == "visual-studio-code", "an abbreviation reaches the popular cask: \(vscode)")
        expect(Set(vscode).count == vscode.count, "no token is listed twice")
    }

    static func resolvesCandidates() throws {
        let index = try index()
        let ready = PackageCandidate(requestedName: "blender", index: index, isFetchingIndex: false, installed: [:])
        guard case .match(let entry, let alternates) = ready.state else {
            return expect(false, "blender resolves to a match")
        }
        expect(entry.token == "blender", "the best match leads")
        expect(alternates.count <= PackageCandidate.alternateLimit, "alternates are capped")
        expect(!alternates.contains(entry), "the lead is not repeated among alternates")
        expect(ready.hasAction, "a match has an action")
        expect(ready.requestedName == "blender", "the typed name is kept for the card")

        let refreshing = PackageCandidate(requestedName: "blender", index: index, isFetchingIndex: true, installed: [:])
        expect(refreshing == ready, "a refresh in flight still serves the index in hand")

        let none = PackageCandidate(requestedName: "xqzjv", index: index, isFetchingIndex: false, installed: [:])
        expect(none.state == .noMatch, "nothing matches")
        expect(!none.hasAction, "no match has no action")

        let loading = PackageCandidate(requestedName: "blender", index: nil, isFetchingIndex: true, installed: [:])
        expect(loading.state == .loadingIndex, "no index yet, one on its way")
        expect(!loading.hasAction, "loading has no action")

        expect(ready.installation == nil, "not in the Caskroom, so the card claims nothing")
        let byBrew = PackageCandidate(
            requestedName: "blender", index: index, isFetchingIndex: false,
            installed: ["blender": installed("blender")])
        expect(byBrew.installation == .installed, "the card says Homebrew installed it")
        expect(byBrew.hasAction, "and still acts, to open it")
        let gone = PackageCandidate(
            requestedName: "blender", index: index, isFetchingIndex: false,
            installed: ["blender": installed("blender", missing: "/Applications/Blender.app")])
        expect(gone.installation == .appMissing("Blender.app"), "the card names the missing app")
        let other = PackageCandidate(
            requestedName: "blender", index: index, isFetchingIndex: false,
            installed: ["zoom": installed("zoom")])
        expect(other.installation == nil, "another cask's record says nothing about this one")

        let missing = PackageCandidate(requestedName: "blender", index: nil, isFetchingIndex: false, installed: [:])
        expect(missing.state == .indexUnavailable, "no index and none coming")
        expect(!missing.hasAction, "an unavailable index has no action")
    }

    // MARK: Record

    static let thisMac = CaskRecord.variation(macOSMajorVersion: 27)

    static func decodesTheAppCask() throws {
        let blender = try CaskRecord.decode(fixture("cask-blender"), variation: thisMac)
        expect(blender.token == "blender", "token")
        expect(blender.names == ["Blender"], "names")
        expect(blender.displayName == "Blender", "the first name is the display name")
        expect(blender.summary == "3D creation suite", "description")
        expect(blender.homepage == URL(string: "https://www.blender.org/"), "homepage")
        expect(blender.downloadURL?.host() == "download.blender.org", "the download host")
        expect(blender.version == "5.3.0", "version")
        expect(
            blender.apps == [.init(source: "Blender.app", target: "/Applications/Blender.app")],
            "the one app artifact, with the target Homebrew resolved")
        expect(blender.apps.first?.installedName == "Blender.app", "the name the app is found by")
        expect(!blender.needsPassword, "an app cask installs without a password")
        expect(blender.disabled == nil && blender.deprecated == nil, "a current cask")
    }

    static func decodesThePkgCask() throws {
        let zoom = try CaskRecord.decode(fixture("cask-zoom"), variation: thisMac)
        expect(zoom.token == "zoom", "token")
        expect(zoom.apps.isEmpty, "a pkg cask names no app artifact")
        expect(zoom.needsPassword, "a pkg installs as root")
        expect(zoom.downloadURL?.host() == "cdn.zoom.us", "the download host")
        expect(zoom.disabled == nil, "not disabled")
    }

    static func decodesTheDisabledCask() throws {
        let alacritty = try CaskRecord.decode(fixture("cask-alacritty"), variation: thisMac)
        expect(
            alacritty.disabled
                == CaskRecord.Retirement(
                    reason: .failsGatekeeperCheck, date: "2026-09-01", replacementCask: nil),
            "disabled, with Homebrew's reason as a typed case")
        expect(alacritty.apps.map(\.installedName) == ["Alacritty.app"], "still names its app")
        expect(!alacritty.needsPassword, "binaries under the user's home need no password")
    }

    static func appliesTheVariationForThisMac() throws {
        expect(CaskRecord.variation(macOSMajorVersion: 26) == "arm64_tahoe", "macOS 26")
        expect(CaskRecord.variation(macOSMajorVersion: 27) == "arm64_golden_gate", "macOS 27")
        expect(CaskRecord.variation(macOSMajorVersion: 28) == nil, "an unknown release takes the base")

        let record = """
            {"token":"cocktail","name":["Cocktail"],"desc":null,"homepage":"https://www.maintain.se/",
             "url":"https://www.maintain.se/downloads/Cocktail20.dmg","version":"20.2.3",
             "artifacts":[{"app":["Cocktail.app"],"target":"/Applications/Cocktail.app"}],
             "disabled":false,"deprecated":false,
             "variations":{"arm64_tahoe":{"url":"https://www.maintain.se/downloads/Cocktail19TE.dmg",
                "version":"19.10.1",
                "artifacts":[{"app":["Cocktail TE.app"],"target":"/Applications/Cocktail TE.app"}]},
              "tahoe":{"version":"0-intel"}}}
            """
        let base = try CaskRecord.decode(Data(record.utf8), variation: "arm64_golden_gate")
        expect(base.version == "20.2.3", "no entry for this release keeps the base")
        let tahoe = try CaskRecord.decode(Data(record.utf8), variation: "arm64_tahoe")
        expect(tahoe.version == "19.10.1", "the release's entry replaces the version")
        expect(tahoe.downloadURL?.lastPathComponent == "Cocktail19TE.dmg", "and the download")
        expect(tahoe.apps.map(\.installedName) == ["Cocktail TE.app"], "and the artifacts")
        expect(tahoe.names == ["Cocktail"], "fields it leaves alone stay")
    }

    static func record(artifacts: String) throws -> CaskRecord {
        let json = """
            {"token":"probe","name":["Probe"],"homepage":"https://example.com/","url":"https://example.com/p.dmg",
             "version":"1.0","disabled":false,"deprecated":false,"artifacts":[\(artifacts)]}
            """
        return try CaskRecord.decode(Data(json.utf8), variation: thisMac)
    }

    static func decidesWhenAnInstallNeedsAPassword() throws {
        let app = #"{"app":["P.app"],"target":"/Applications/P.app"}"#
        let cases: [(String, String, Bool)] = [
            ("an installer script run with sudo",
             #"{"installer":[{"script":{"executable":"Setup.app/Contents/MacOS/Setup","sudo":true}}]}"#, true),
            ("an installer script run as the user",
             #"{"installer":[{"script":{"executable":"Setup.app/Contents/MacOS/Setup","sudo":false}}]}"#, false),
            ("a postflight step with sudo if needed",
             #"{"postflight_steps":[{"steps":[{"type":"symlink","sudo":"if_needed"}]}]}"#, true),
            ("a preflight step with sudo",
             #"{"preflight_steps":[{"steps":[{"type":"set_permissions","sudo":true}]}]}"#, true),
            ("a keyboard layout in /Library",
             #"{"keyboard_layout":["bepo.bundle"],"target":"/Library/Keyboard Layouts/bepo.bundle"}"#, true),
            ("a binary in /usr/local",
             #"{"binary":["$APPDIR/X.app/x"],"target":"/usr/local/bin/x"}"#, true),
            ("an uninstall step with sudo, which only runs on uninstall",
             #"{"uninstall":[{"script":{"executable":"rm","sudo":true}}]},"# + app, false),
            ("a zap step with sudo",
             #"{"zap":[{"script":{"executable":"rm","sudo":true}}]},"# + app, false),
            ("a binary under the Homebrew prefix",
             app + #",{"binary":["$APPDIR/P.app/p"],"target":"$HOMEBREW_PREFIX/bin/p"}"#, false),
        ]
        for (label, artifacts, needs) in cases {
            expect(try record(artifacts: artifacts).needsPassword == needs, "\(label): \(needs)")
        }

        let manual = try record(artifacts: #"{"installer":[{"manual":"Battle.net-Setup.app"}]}"#)
        expect(manual.hasManualInstaller, "an installer the user must open")
        expect(!manual.needsPassword, "which is a different reason from a password")
        let scripted = try record(artifacts: #"{"installer":[{"script":{"executable":"x","sudo":false}}]}"#)
        expect(!scripted.hasManualInstaller, "a scripted installer runs by itself")
        let blender = try CaskRecord.decode(fixture("cask-blender"), variation: thisMac)
        expect(!blender.hasManualInstaller, "an app cask has no manual step")
    }

    static func refusesMalformedRecords() {
        let records: [(String, String)] = [
            ("an HTML error page", "<html>404</html>"),
            ("an array", "[]"),
            ("no token", #"{"name":["X"],"version":"1","artifacts":[]}"#),
            ("a token brew would not accept", #"{"token":"x; rm -rf ~","name":["X"],"version":"1","artifacts":[]}"#),
            ("no version", #"{"token":"x","name":["X"],"artifacts":[]}"#),
            ("no artifacts", #"{"token":"x","name":["X"],"version":"1"}"#),
            ("an app with no target", #"{"token":"x","name":["X"],"version":"1","artifacts":[{"app":["X.app"]}]}"#),
        ]
        for (label, body) in records {
            expect((try? CaskRecord.decode(Data(body.utf8), variation: thisMac)) == nil, "\(label) is refused")
        }
    }

    static func shapesTheVersion() throws {
        func version(_ raw: String) throws -> String? {
            let json = """
                {"token":"v","name":["V"],"url":"https://example.com/v.dmg","version":"\(raw)","artifacts":[]}
                """
            return try CaskRecord.decode(Data(json.utf8), variation: nil).displayVersion
        }
        expect(try version("5.3.0") == "5.3.0", "a plain version shows as it is")
        expect(try version("latest") == nil, "an unversioned cask shows no version")
        expect(try version("256,142-53583-20261104") == "256", "Homebrew's build suffix is dropped")
        let unnamed = try CaskRecord.decode(
            Data(#"{"token":"no-name","name":[],"version":"1","artifacts":[]}"#.utf8), variation: nil)
        expect(unnamed.displayName == "no-name", "a cask with no name shows its token")
    }

    // MARK: Plan

    static let brew = URL(fileURLWithPath: "/opt/homebrew/bin/brew")

    static func buildsOnlySafeInvocations() {
        let invocation = BrewInvocation(brew: brew, token: "blender")
        expect(invocation?.displayText == "brew install --cask blender", "the dialog's Runs line")
        expect(
            invocation?.arguments == ["/opt/homebrew/bin/brew", "install", "blender"],
            "brew, the verb and the token, positional")
        let reinstall = BrewInvocation(brew: brew, token: "blender", verb: .reinstall)
        expect(reinstall?.displayText == "brew reinstall --cask blender", "a reinstall says so")
        expect(reinstall?.arguments == ["/opt/homebrew/bin/brew", "reinstall", "blender"], "and runs so")
        expect(BrewInvocation(brew: brew, token: "x;reboot") == nil, "an unsafe token builds nothing")
        expect(BrewInvocation(brew: brew, token: "--force") == nil, "an option builds nothing")
        let script = BrewInvocation.script
        expect(script.contains(#"exec "$1" "$2" --cask "$3""#), "the script runs only its positional values")
        for setting in ["HOMEBREW_NO_SUDO=1", "HOMEBREW_NO_ASK=1", "HOMEBREW_CASK_OPTS=", "HOMEBREW_NO_ANALYTICS=1"] {
            expect(script.contains(setting), "the script sets \(setting)")
        }
        expect(!script.contains("blender"), "no token is ever spliced into the script")
    }

    static func writesTheTerminalScript() {
        let script = BrewInvocation(brew: brew, token: "zoom")!.terminalScript
        let lines = script.split(separator: "\n").map(String.init)
        expect(lines.first == "#!/bin/zsh", "zsh runs it, whatever the user's shell")
        expect(lines.contains(#"rm -f -- "$0""#), "the file deletes itself once Terminal has it")
        expect(
            lines.last == "HOMEBREW_NO_ANALYTICS=1 exec '/opt/homebrew/bin/brew' install --cask 'zoom'",
            "the same command, by absolute path, quoted: \(lines.last ?? "")")
        expect(script.contains("brew install --cask zoom"), "it shows the command the dialog named")
        expect(!script.contains("HOMEBREW_NO_SUDO"), "Terminal is where sudo is allowed to ask")
        let reinstall = BrewInvocation(brew: brew, token: "blender", verb: .reinstall)!.terminalScript
        expect(
            reinstall.hasSuffix("exec '/opt/homebrew/bin/brew' reinstall --cask 'blender'"),
            "a reinstall runs reinstall in Terminal")
        expect(reinstall.contains("print -r -- 'brew reinstall --cask blender'"), "and shows it")
        let odd = BrewInvocation(brew: URL(fileURLWithPath: "/tmp/it's here/brew"), token: "zoom")!
        expect(
            odd.terminalScript.contains(#"exec '/tmp/it'\''s here/brew' install"#),
            "a quote in the path cannot end the quoting")
    }

    static func recognisesARefusedSudo() {
        let log = "==> Installing Cask zoom\nError: Failure while executing; `/usr/bin/sudo -E -- /usr/sbin/installer`"
            + " exited with 1. Here's the output:\nsudo is disabled by HOMEBREW_NO_SUDO.\n"
        expect(BrewInvocation.refusedSudo(in: log), "Homebrew's own message, mid-log")
        expect(BrewInvocation.refusedSudo(in: "sudo is disabled by HOMEBREW_NO_SUDO.\r\n"), "with a pty's line end")
        expect(!BrewInvocation.refusedSudo(in: "Error: Download failed"), "another failure")
        expect(!BrewInvocation.refusedSudo(in: ""), "no output")
    }

    static func resolvesTargetsUnderHome() throws {
        let home = "/Users/someone"
        func path(_ target: String) -> String {
            CaskRecord.AppArtifact(source: "A.app", target: target).path(home: home)
        }
        expect(path("/Applications/A.app") == "/Applications/A.app", "an absolute target is kept")
        expect(path("/$HOME/Library/Box/A.app") == "/Users/someone/Library/Box/A.app", "Homebrew's /$HOME")
        expect(path("$HOME/Applications/A.app") == "/Users/someone/Applications/A.app", "a bare $HOME")
        expect(path("~/Applications/A.app") == "/Users/someone/Applications/A.app", "a tilde")
        expect(path("/Applications/$HOMEBREW/A.app") == "/Applications/$HOMEBREW/A.app", "only a leading $HOME")
    }

    static func installed(_ token: String, missing: String? = nil) -> InstalledCask {
        let path = "/Applications/\(token).app"
        return InstalledCask(token: token, appPaths: [missing ?? path], missingAppPaths: missing.map { [$0] } ?? [])
    }

    static func plansEveryOutcome() throws {
        let blender = try CaskRecord.decode(fixture("cask-blender"), variation: thisMac)
        let zoom = try CaskRecord.decode(fixture("cask-zoom"), variation: thisMac)
        let alacritty = try CaskRecord.decode(fixture("cask-alacritty"), variation: thisMac)
        let clean = InstallPlan.Facts(brew: brew, installedCasks: [:], presentAppNames: ["Safari.app"])
        let invocation = BrewInvocation(brew: brew, token: "blender")!

        expect(InstallPlan.make(record: blender, facts: clean) == .install(invocation), "a clean install")
        expect(
            InstallPlan.make(record: zoom, facts: clean) == .terminal(BrewInvocation(brew: brew, token: "zoom")!),
            "a pkg goes to Terminal")
        expect(
            InstallPlan.make(record: alacritty, facts: clean) == .disabled(alacritty.disabled!),
            "a disabled cask is refused with its reason")

        let noBrew = InstallPlan.Facts(brew: nil, installedCasks: [:], presentAppNames: [])
        expect(InstallPlan.make(record: blender, facts: noBrew) == .homebrewMissing, "no Homebrew")
        expect(InstallPlan.make(record: zoom, facts: noBrew) == .homebrewMissing, "no Homebrew, pkg too")

        let byHand = InstallPlan.Facts(brew: brew, installedCasks: [:], presentAppNames: ["Blender.app"])
        expect(
            InstallPlan.make(record: blender, facts: byHand)
                == .alreadyInstalled(appName: "Blender.app", byHomebrew: false),
            "an app installed by hand is opened, not overwritten")
        let byHandNoBrew = InstallPlan.Facts(brew: nil, installedCasks: [:], presentAppNames: ["Blender.app"])
        expect(
            InstallPlan.make(record: blender, facts: byHandNoBrew)
                == .alreadyInstalled(appName: "Blender.app", byHomebrew: false),
            "a present app needs no Homebrew to open")

        let byBrew = InstallPlan.Facts(
            brew: brew, installedCasks: ["blender": installed("blender")], presentAppNames: ["Blender.app"])
        expect(
            InstallPlan.make(record: blender, facts: byBrew)
                == .alreadyInstalled(appName: "Blender.app", byHomebrew: true),
            "a cask Homebrew already installed")
        let pkgByBrew = InstallPlan.Facts(brew: brew, installedCasks: ["zoom": installed("zoom")], presentAppNames: [])
        expect(
            InstallPlan.make(record: zoom, facts: pkgByBrew) == .alreadyInstalled(appName: nil, byHomebrew: true),
            "a pkg is known only by Homebrew's record")
        let appRemoved = InstallPlan.Facts(
            brew: brew, installedCasks: ["blender": installed("blender", missing: "/Applications/Blender.app")],
            presentAppNames: [])
        expect(
            InstallPlan.make(record: blender, facts: appRemoved)
                == .reinstall(BrewInvocation(brew: brew, token: "blender", verb: .reinstall)!, missingApp: "Blender.app"),
            "Homebrew lists it but its app was deleted: a reinstall in Terminal, not \"already installed\"")
        let appRemovedNoBrew = InstallPlan.Facts(
            brew: nil, installedCasks: ["blender": installed("blender", missing: "/Applications/Blender.app")],
            presentAppNames: [])
        expect(
            InstallPlan.make(record: blender, facts: appRemovedNoBrew) == .homebrewMissing,
            "a reinstall needs brew too")
        let appMoved = InstallPlan.Facts(
            brew: brew, installedCasks: ["blender": installed("blender", missing: "/Applications/Blender.app")],
            presentAppNames: ["Blender.app"])
        expect(
            InstallPlan.make(record: blender, facts: appMoved)
                == .alreadyInstalled(appName: "Blender.app", byHomebrew: true),
            "an app moved somewhere the launcher still finds is not missing")

        let manual = try record(artifacts: #"{"installer":[{"manual":"Setup.app"}]}"#)
        expect(
            InstallPlan.make(record: manual, facts: clean) == .terminal(BrewInvocation(brew: brew, token: "probe")!),
            "a manual installer goes to Terminal, where Homebrew says what to open")

        let disabledAndPresent = InstallPlan.Facts(brew: brew, installedCasks: [:], presentAppNames: ["Alacritty.app"])
        expect(
            InstallPlan.make(record: alacritty, facts: disabledAndPresent) == .disabled(alacritty.disabled!),
            "disabled is decided before presence")

        let unsafe = CaskRecord(
            token: "x;reboot", names: ["X"], summary: nil, homepage: nil, downloadURL: nil, version: "1",
            apps: [], needsPassword: false, hasManualInstaller: false, disabled: nil, deprecated: nil)
        expect(InstallPlan.make(record: unsafe, facts: clean) == .invalidToken, "a record built by hand is rechecked")
    }

    // MARK: Receipts and approval

    static func receipt(_ artifacts: String) -> Data {
        Data(#"{"homebrew_version":"7.0.13","uninstall_artifacts":[\#(artifacts)]}"#.utf8)
    }

    static func readsInstallReceipts() {
        let home = "/Users/someone"
        let plain = InstalledCask.appPaths(
            receipt: receipt(#"{"app":["Obsidian.app"]},{"zap":[{"trash":"~/x"}]}"#), config: nil, home: home)
        expect(plain == ["/Applications/Obsidian.app"], "an app goes to /Applications by default")
        let renamed = InstalledCask.appPaths(
            receipt: receipt(#"{"app":["Thorium.app",{"target":"Thorium Browser.app"}]}"#), config: nil, home: home)
        expect(renamed == ["/Applications/Thorium Browser.app"], "a renaming target is where it went")
        let config = Data(#"{"default":{"appdir":"/Applications"},"env":{},"explicit":{"appdir":"~/Apps"}}"#.utf8)
        let custom = InstalledCask.appPaths(receipt: receipt(#"{"app":["A.app"]}"#), config: config, home: home)
        expect(custom == ["/Users/someone/Apps/A.app"], "an explicit app folder from the install wins")
        let absolute = InstalledCask.appPaths(
            receipt: receipt(#"{"app":["Box.app",{"target":"~/Library/Box/Box.app"}]}"#), config: config, home: home)
        expect(absolute == ["/Users/someone/Library/Box/Box.app"], "a target under home is kept whole")
        let nested = InstalledCask.appPaths(
            receipt: receipt(#"{"app":["Install X.app/Contents/Resources/X.app"]}"#), config: nil, home: home)
        expect(nested == ["/Applications/X.app"], "a nested source installs under its own name")
        expect(InstalledCask.appPaths(receipt: receipt(#"{"pkg":["x.pkg"]}"#), config: nil, home: home).isEmpty, "a pkg")
        expect(InstalledCask.appPaths(receipt: Data("{}".utf8), config: nil, home: home).isEmpty, "an old receipt")
        expect(InstalledCask.appPaths(receipt: Data("nope".utf8), config: nil, home: home).isEmpty, "a broken one")
        let gone = InstalledCask(token: "a", appPaths: ["/Applications/A.app"], missingAppPaths: ["/Applications/A.app"])
        expect(gone.missingAppName == "A.app", "the missing app's name, for the card")
    }

    static func writesTheApproval() throws {
        let blender = try CaskRecord.decode(fixture("cask-blender"), variation: thisMac)
        let message = InstallApproval.message(record: blender, invocation: BrewInvocation(brew: brew, token: "blender")!)
        expect(
            message == """
                Blender 5.3.0 · 3D creation suite
                Source: blender.org, Homebrew cask “blender”
                Download from: download.blender.org
                Runs: brew install --cask blender
                Installs to: /Applications/Blender.app
                """,
            "every line from the record, and the exact command:\n\(message)")
        let zoom = try CaskRecord.decode(fixture("cask-zoom"), variation: thisMac)
        let pkg = InstallApproval.message(record: zoom, invocation: BrewInvocation(brew: brew, token: "zoom")!)
        expect(!pkg.contains("Installs to"), "a pkg names no app folder")
        let bare = CaskRecord(
            token: "bare", names: [], summary: nil, homepage: nil, downloadURL: nil, version: "latest",
            apps: [], needsPassword: false, hasManualInstaller: false, disabled: nil,
            deprecated: .init(reason: .discontinued, date: nil, replacementCask: "bare-two"))
        let sparse = InstallApproval.message(record: bare, invocation: BrewInvocation(brew: brew, token: "bare")!)
        expect(sparse.hasPrefix("bare\n"), "no version, no description: just the name")
        expect(sparse.contains("Source: Homebrew cask “bare”"), "no homepage: only the cask")
        expect(sparse.contains("bare-two"), "a deprecated cask names its replacement")
    }

    static func namesEveryRetirementReason() {
        let reasons: [CaskRecord.Retirement.Reason] = [
            .discontinued, .noLongerAvailable, .noLongerMeetsCriteria, .unmaintained, .unreachable,
            .failsGatekeeperCheck, .movedToMacAppStore, .stated("requires a login to download"),
        ]
        for reason in reasons {
            expect(!reason.sentence.isEmpty, "\(reason) reads as a sentence")
        }
        expect(
            CaskRecord.Retirement.Reason.stated("requires a login to download").sentence
                .contains("requires a login to download"),
            "a cask's own words are kept")
    }

    // MARK: Verification

    static func judgesEveryVerification() {
        typealias Observation = InstallVerification.Observation
        expect(
            InstallVerification.judge(Observation(hasCaskroomEntry: true, missingApps: [], untrustedApps: []))
                == .verified,
            "every check passed")
        expect(
            InstallVerification.judge(
                Observation(hasCaskroomEntry: false, missingApps: ["Blender.app"], untrustedApps: []))
                == .noCaskroomEntry,
            "Homebrew's own record is checked first")
        expect(
            InstallVerification.judge(
                Observation(hasCaskroomEntry: true, missingApps: ["Blender.app"], untrustedApps: ["Blender.app"]))
                == .appMissing("Blender.app"),
            "a missing app is named before a signature")
        expect(
            InstallVerification.judge(Observation(hasCaskroomEntry: true, missingApps: [], untrustedApps: ["A.app"]))
                == .appUntrusted("A.app"),
            "an app sealed by neither Apple nor a Developer ID")
    }
}
