import Foundation
import Synchronization

/// No case runs the real `brew`: a fake one in a scratch prefix stands in for it.
@main
@MainActor
struct PackageInstallServiceTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        if (try? condition()) == true {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        try await fetchesOneRecord()
        try await mapsRecordFailures()
        try await reportsCancellationAsCancellation()
        try await findsBrewAndTheCaskroom()
        try await noticesAnAppDeletedByHand()
        try await installsThroughTheFixedScript()
        try await passesBrewsExitStatusThrough()
        try await stopsALongInstall()
        try await reportsARefusedSudo()
        try await observesAnInstall()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: "Tests/package-fixtures/\(name).json"))
    }

    static func scratch(_ name: String = "") throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "PackageInstallServiceTests-\(UUID().uuidString)\(name)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: CaskAPI

    static let base = URL(string: "https://brew.test/api/")!
    static let session = CaskAPI.session(protocolClasses: [RecordFixture.self])
    static let thisMac = CaskRecord.variation(macOSMajorVersion: 27)

    static func fetchesOneRecord() async throws {
        RecordFixture.reset(.serve(200, try fixture("cask-blender")))
        let record = try await CaskAPI.record(token: "blender", variation: thisMac, baseURL: base, session: session)
        expect(record.token == "blender", "the record decodes")
        expect(RecordFixture.paths == ["/api/cask/blender.json"], "one request, for that token's file")
    }

    static func failure(_ token: String = "blender") async -> CaskAPI.Failure? {
        do {
            _ = try await CaskAPI.record(token: token, variation: thisMac, baseURL: base, session: session)
            return nil
        } catch let failure as CaskAPI.Failure {
            return failure
        } catch {
            return nil
        }
    }

    static func mapsRecordFailures() async throws {
        RecordFixture.reset(.serve(404, Data("Not Found".utf8)))
        let outcome1 = await failure()
        expect(outcome1 == .notFound, "a 404 is a cask Homebrew no longer has")
        RecordFixture.reset(.serve(503, try fixture("cask-blender")))
        let outcome2 = await failure()
        expect(outcome2 == .unavailable, "any other status is unavailable")
        RecordFixture.reset(.offline)
        let outcome3 = await failure()
        expect(outcome3 == .unavailable, "no network is unavailable")
        RecordFixture.reset(.serve(200, Data("<html>maintenance</html>".utf8)))
        let outcome4 = await failure()
        expect(outcome4 == .malformed, "a page that is not a record")
        RecordFixture.reset(.serve(200, try fixture("cask-zoom")))
        let outcome5 = await failure()
        expect(outcome5 == .malformed, "a record for a different token")
        RecordFixture.reset(.serve(200, try fixture("cask-blender")))
        let outcome6 = await failure("../etc")
        expect(outcome6 == .notFound, "a token brew would refuse is never requested")
        expect(RecordFixture.paths.isEmpty, "not even once")
    }

    static func reportsCancellationAsCancellation() async throws {
        RecordFixture.reset(.hold)
        let fetch = Task {
            try await CaskAPI.record(token: "blender", variation: thisMac, baseURL: base, session: session)
        }
        await expectSettles("the request is in flight") { RecordFixture.paths.count == 1 }
        fetch.cancel()
        do {
            _ = try await fetch.value
            expect(false, "a cancelled fetch returns no record")
        } catch is CancellationError {
            expect(true, "cancelling is a CancellationError, never an ordinary failure")
        } catch {
            expect(false, "cancelling threw \(error) instead of CancellationError")
        }
    }

    // MARK: HomebrewEnvironment

    /// A prefix laid out as Homebrew lays out `/opt/homebrew`.
    static func prefix(brewScript: String? = nil, casks: [String] = []) throws -> URL {
        let prefix = try scratch()
        if let brewScript {
            let bin = prefix.appending(path: "bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let brew = bin.appending(path: "brew")
            try Data(brewScript.utf8).write(to: brew)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        }
        for cask in casks {
            let record = prefix.appending(path: "Caskroom/\(cask)/.metadata/1.0/20261113162214.367/Casks")
            try FileManager.default.createDirectory(at: record, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: record.appending(path: "\(cask).json"))
        }
        return prefix
    }

    /// Ctrl-C at Terminal's password prompt left blackhole-2ch like this on 2026-11-13.
    static func interruptInstall(_ cask: String, in prefix: URL) throws {
        let caskroom = prefix.appending(path: "Caskroom/\(cask)")
        try FileManager.default.createDirectory(
            at: caskroom.appending(path: ".metadata/0.7.1/20261113162056.399/Casks"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: caskroom.appending(path: "0.7.1"), withIntermediateDirectories: true)
        try Data().write(to: caskroom.appending(path: "0.7.1/Driver.pkg"))
    }

    static func receipt(_ app: String) -> Data {
        Data(#"{"uninstall_artifacts":[{"app":["\#(app)"]}]}"#.utf8)
    }

    /// Prowlarr and Wine Stable on the owner's Mac: Homebrew's record outlived the app.
    static func noticesAnAppDeletedByHand() async throws {
        let prefix = try prefix(casks: ["kept", "deleted", "tool"])
        let apps = try scratch()
        let config = Data(#"{"default":{"appdir":"\#(apps.path)"},"env":{},"explicit":{}}"#.utf8)
        for (cask, app) in [("kept", "Kept.app"), ("deleted", "Deleted.app")] {
            let metadata = prefix.appending(path: "Caskroom/\(cask)/.metadata")
            try receipt(app).write(to: metadata.appending(path: "INSTALL_RECEIPT.json"))
            try config.write(to: metadata.appending(path: "config.json"))
        }
        try FileManager.default.createDirectory(
            at: apps.appending(path: "Kept.app/Contents"), withIntermediateDirectories: true)
        let installed = await HomebrewEnvironment.installedCasks(prefix: prefix, home: "/nowhere")
        expect(installed["kept"]?.missingAppPaths == [], "an app where its receipt says is not missing")
        expect(installed["kept"]?.appPaths == [apps.appending(path: "Kept.app").path], "at the recorded folder")
        expect(installed["deleted"]?.missingAppName == "Deleted.app", "a deleted app is named as missing")
        expect(installed["tool"]?.appPaths == [], "a cask with no receipt still counts, with no apps")
    }

    static func findsBrewAndTheCaskroom() async throws {
        let empty = try prefix()
        expect(HomebrewEnvironment.brew(prefix: empty) == nil, "no brew in an empty prefix")
        let nothing = await HomebrewEnvironment.installedCasks(prefix: empty, home: "/nowhere")
        expect(nothing.isEmpty, "and no Caskroom")

        let full = try prefix(brewScript: "#!/bin/sh\n", casks: ["blender", "zoom"])
        expect(
            HomebrewEnvironment.brew(prefix: full) == full.appending(path: "bin/brew"),
            "an executable brew in bin is found")
        try FileManager.default.createDirectory(
            at: full.appending(path: "Caskroom/half-done/1.0"), withIntermediateDirectories: true)
        try Data().write(to: full.appending(path: "Caskroom/.DS_Store"))
        try interruptInstall("blackhole-2ch", in: full)
        let installed = await HomebrewEnvironment.installedCasks(prefix: full, home: "/nowhere")
        expect(
            Set(installed.keys) == ["blender", "zoom"],
            "a cask counts once Homebrew recorded it; an interrupted install and stray files never do")

        let unexecutable = try prefix(brewScript: "#!/bin/sh\n")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: unexecutable.appending(path: "bin/brew").path)
        expect(HomebrewEnvironment.brew(prefix: unexecutable) == nil, "a brew that cannot run is no brew")
    }

    // MARK: CaskInstaller

    /// Prints what it was given, then behaves as the token asks.
    static let fakeBrew = """
        #!/bin/sh
        echo "args:$*"
        echo "sudo:$HOMEBREW_NO_SUDO ask:$HOMEBREW_NO_ASK analytics:$HOMEBREW_NO_ANALYTICS opts:<$HOMEBREW_CASK_OPTS>"
        case "$3" in
            fail) echo "Error: Download failed"; exit 3 ;;
            slow) echo "downloading"; sleep 30 ;;
            needs-sudo) echo "sudo is disabled by HOMEBREW_NO_SUDO."; exit 1 ;;
        esac
        echo "installed $3"
        """

    static func run(_ token: String, prefixName: String = "") async throws -> (String, ShellCommandResult?) {
        let prefix = try prefix(brewScript: fakeBrew)
        let folder = try scratch(prefixName)
        try FileManager.default.moveItem(at: prefix.appending(path: "bin"), to: folder.appending(path: "bin"))
        let invocation = BrewInvocation(brew: folder.appending(path: "bin/brew"), token: token)!
        let session = CaskInstaller.install(invocation)
        var output = ""
        var result: ShellCommandResult?
        for await event in session.events {
            switch event {
            case .output(let text): output += text
            case .finished(let finished): result = finished
            }
        }
        return (output, result)
    }

    static func installsThroughTheFixedScript() async throws {
        setenv("HOMEBREW_CASK_OPTS", "--appdir=/tmp/elsewhere", 1)
        defer { unsetenv("HOMEBREW_CASK_OPTS") }
        let (output, result) = try await run("blender", prefixName: " it's spaced")
        expect(result?.termination == .exited(status: 0), "brew's success is the run's success")
        expect(output.contains("args:install --cask blender"), "brew gets exactly install --cask TOKEN")
        expect(output.contains("sudo:1 ask:1 analytics:1"), "no sudo, no asking, no analytics: \(output)")
        expect(output.contains("opts:<>"), "an inherited HOMEBREW_CASK_OPTS is cleared")
        expect(output.contains("installed blender"), "the output streams through")
    }

    static func passesBrewsExitStatusThrough() async throws {
        let (output, result) = try await run("fail")
        expect(result?.termination == .exited(status: 3), "a failed brew is a failed run")
        expect(output.contains("Error: Download failed"), "with Homebrew's own words kept")
    }

    static func stopsALongInstall() async throws {
        let prefix = try prefix(brewScript: fakeBrew)
        let session = CaskInstaller.install(BrewInvocation(brew: prefix.appending(path: "bin/brew"), token: "slow")!)
        let started = ContinuousClock.now
        var stopped = false
        var termination: ShellCommandTermination?
        for await event in session.events {
            switch event {
            case .output(let text) where text.contains("downloading") && !stopped:
                stopped = true
                session.stop()
            case .finished(let result): termination = result.termination
            default: break
            }
        }
        expect(termination == .stopped, "Stop ends the run as stopped, not as a failure")
        expect(ContinuousClock.now - started < .seconds(5), "within the runner's grace, not brew's 30 s")
    }

    static func reportsARefusedSudo() async throws {
        let (output, result) = try await run("needs-sudo")
        expect(result?.succeeded == false, "a refused sudo fails the run")
        expect(BrewInvocation.refusedSudo(in: output), "and is recognised, so the flow can offer Terminal")
    }

    // MARK: InstallVerifier

    static func record(target: String) -> CaskRecord {
        CaskRecord(
            token: "probe", names: ["Probe"], summary: nil, homepage: nil, downloadURL: nil, version: "1",
            apps: [.init(source: "Probe.app", target: target)], needsPassword: false,
            hasManualInstaller: false, disabled: nil, deprecated: nil)
    }

    static func observesAnInstall() async throws {
        let home = try scratch()
        let installed = try prefix(casks: ["probe"])
        let bare = try prefix()

        let missing = await InstallVerifier.observe(
            record: record(target: "/$HOME/Applications/Probe.app"), prefix: installed, home: home.path)
        expect(missing.hasCaskroomEntry, "Homebrew's record is seen")
        try interruptInstall("probe", in: bare)
        let interrupted = await InstallVerifier.observe(
            record: record(target: "/$HOME/Applications/Probe.app"), prefix: bare, home: home.path)
        expect(!interrupted.hasCaskroomEntry, "an interrupted install's folder is no record")
        expect(missing.missingApps == ["Probe.app"], "an app that is not at its target is missing")

        let app = home.appending(path: "Applications/Probe.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let unsigned = await InstallVerifier.observe(
            record: record(target: "/$HOME/Applications/Probe.app"), prefix: installed, home: home.path)
        expect(unsigned.missingApps.isEmpty, "the app under the home folder is found")
        expect(unsigned.untrustedApps == ["Probe.app"], "an unsealed bundle fails the signature check")

        let executable = home.appending(path: "Applications/Probe.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: executable, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: executable.appending(path: "Probe").path)
        try Data(#"<plist version="1.0"><dict><key>CFBundleExecutable</key><string>Probe</string></dict></plist>"#.utf8)
            .write(to: app.appending(path: "Info.plist"))
        expect(try codesign(home.appending(path: "Applications/Probe.app")), "the probe is ad-hoc signed")
        let adHoc = await InstallVerifier.observe(
            record: record(target: "/$HOME/Applications/Probe.app"), prefix: installed, home: home.path)
        expect(adHoc.untrustedApps == ["Probe.app"], "an ad-hoc seal is no one's, so it fails too")

        let apple = await InstallVerifier.observe(
            record: record(target: "/System/Applications/Calculator.app"), prefix: bare, home: home.path)
        expect(!apple.hasCaskroomEntry, "no Caskroom entry")
        expect(apple.missingApps.isEmpty, "Calculator is there")
        expect(apple.untrustedApps.isEmpty, "Apple's own signature is trusted as well as a Developer ID")
        expect(InstallVerification.judge(apple) == .noCaskroomEntry, "judged on the first failed check")
    }

    static func codesign(_ bundle: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", bundle.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.runObservingExit().wait()
        return process.terminationStatus == 0
    }

    static func expectSettles(_ message: String, within seconds: Double = 5, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition() {
            guard ContinuousClock.now < deadline else { return expect(false, message) }
            try? await Task.sleep(for: .milliseconds(10))
        }
        expect(true, message)
    }
}

/// URL loading owns each instance; the shared reply and request log are guarded by a mutex.
private final class RecordFixture: URLProtocol, @unchecked Sendable {
    enum Mode {
        case serve(Int, Data)
        case offline
        case hold
    }

    private static let state = Mutex<(mode: Mode, paths: [String])>((.offline, []))

    static var paths: [String] { state.withLock { $0.paths } }
    static func reset(_ mode: Mode) { state.withLock { $0 = (mode, []) } }

    override static func canInit(with request: URLRequest) -> Bool { request.url?.host == "brew.test" }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let mode = Self.state.withLock { state in
            state.paths.append(request.url?.path ?? "")
            return state.mode
        }
        switch mode {
        case .serve(let status, let data):
            guard let url = request.url,
                let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .hold:
            break
        }
    }

    override func stopLoading() {}
}
