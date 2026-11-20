// Phase L step 2: throwaway capture spike. Deleted when step 5's ScreenCapturer lands.
import AppKit
import CoreGraphics
import ScreenCaptureKit
import Security

@main
@MainActor
enum LookCaptureSpike {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let options = Options(arguments: Array(CommandLine.arguments.dropFirst()))
        Task { @MainActor in
            await Run(options: options).start()
            NSApp.terminate(nil)
        }
        app.run()
    }
}

struct Options {
    var mode = "status"
    var excludeSelf = false
    var excludeBundles: [String] = []
    var decoys = false
    var delay = 0.0
    var hold = 0.0
    var repeatCount = 1
    var interval = 1.0
    var wait = 180.0
    var save: String?
    var report = NSString(string: "~/Library/Logs/LookCaptureSpike.log").expandingTildeInPath

    init(arguments: [String]) {
        var args = arguments[...]
        if let first = args.first, !first.hasPrefix("-") { mode = first; args = args.dropFirst() }
        while let arg = args.popFirst() {
            switch arg {
            case "--exclude-self": excludeSelf = true
            case "--exclude-bundle": excludeBundles.append(args.popFirst() ?? "")
            case "--decoys": decoys = true
            case "--delay": delay = Double(args.popFirst() ?? "") ?? 0
            case "--hold": hold = Double(args.popFirst() ?? "") ?? 0
            case "--repeat": repeatCount = Int(args.popFirst() ?? "") ?? 1
            case "--interval": interval = Double(args.popFirst() ?? "") ?? 1
            case "--wait": wait = Double(args.popFirst() ?? "") ?? 180
            case "--save": save = args.popFirst().map { NSString(string: $0).expandingTildeInPath }
            case "--report": report = NSString(string: args.popFirst() ?? report).expandingTildeInPath
            default: break
            }
        }
    }
}

@MainActor
final class Run {
    let options: Options
    private var decoyWindows: [Decoy] = []

    init(options: Options) { self.options = options }

    func start() async {
        log("---- \(options.mode) \(CommandLine.arguments.dropFirst().joined(separator: " "))")
        log("pid \(getpid()) bundle \(Bundle.main.bundleIdentifier ?? "-") stamp \(buildStamp)")
        log("cdhash \(Self.cdhash() ?? "unknown") macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        log("preflight \(CGPreflightScreenCaptureAccess())")
        switch options.mode {
        case "request": await request()
        case "capture": await captureRuns()
        default: break
        }
    }

    private func request() async {
        if CGPreflightScreenCaptureAccess() {
            log("already granted; no request made")
        } else {
            let answer = CGRequestScreenCaptureAccess()
            log("CGRequestScreenCaptureAccess returned \(answer)")
        }
        let started = Date()
        var lastPreflight = CGPreflightScreenCaptureAccess()
        var tick = 0
        while Date().timeIntervalSince(started) < options.wait {
            try? await Task.sleep(for: .seconds(1))
            tick += 1
            let now = CGPreflightScreenCaptureAccess()
            if now != lastPreflight { log("t+\(tick)s preflight changed to \(now)") }
            lastPreflight = now
            if tick % 5 == 0 {
                let ok = await tryCapture(label: "t+\(tick)s in-process")
                if ok { break }
            }
        }
        log("request done after \(tick)s; preflight \(CGPreflightScreenCaptureAccess())")
    }

    @discardableResult
    private func tryCapture(label: String) async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { log("\(label): no display"); return false }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration(for: display))
            log("\(label): capture ok \(image.width)x\(image.height), \(content.windows.count) windows listed")
            return true
        } catch {
            log("\(label): capture failed: \(error.localizedDescription) [\((error as NSError).code)]")
            return false
        }
    }

    private func captureRuns() async {
        if options.decoys { showDecoys() }
        if options.delay > 0 {
            log("waiting \(options.delay)s before capture")
            try? await Task.sleep(for: .seconds(options.delay))
        }
        for index in 0..<max(1, options.repeatCount) {
            if index > 0 { try? await Task.sleep(for: .seconds(options.interval)) }
            await captureOnce(index: index)
        }
        if options.hold > 0 {
            log("holding \(options.hold)s after the last capture")
            try? await Task.sleep(for: .seconds(options.hold))
        }
        decoyWindows.forEach { $0.window.orderOut(nil) }
    }

    private func captureOnce(index: Int) async {
        let clock = ContinuousClock()
        let begin = clock.now
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            log("#\(index) SCShareableContent failed: \(error.localizedDescription) [\((error as NSError).code)]")
            return
        }
        let listed = clock.now
        guard let screen = Self.screenUnderPointer(),
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
            let display = content.displays.first(where: { $0.displayID == displayID })
        else {
            log("#\(index) no SCDisplay matches the screen under the pointer")
            return
        }
        let excluded = content.applications.filter { app in
            (options.excludeSelf && app.processID == getpid())
                || options.excludeBundles.contains(app.bundleIdentifier)
        }
        log("#\(index) display \(displayID) of \(content.displays.count), \(display.width)x\(display.height) pt")
        log("#\(index) excluding \(excluded.map { "\($0.bundleIdentifier)(\($0.processID))" })")
        for bundle in options.excludeBundles where !excluded.contains(where: { $0.bundleIdentifier == bundle }) {
            log("#\(index) WARNING \(bundle) not running or not listed")
        }
        for app in excluded {
            let windows = content.windows.filter { $0.owningApplication?.processID == app.processID }
            for window in windows {
                log("#\(index)   \(app.bundleIdentifier) window \(window.windowID) layer \(window.windowLayer) "
                    + "frame \(window.frame) onScreen \(window.isOnScreen)")
            }
        }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration(for: display))
            let done = clock.now
            log("#\(index) image \(image.width)x\(image.height); list \(ms(listed - begin)) ms, "
                + "capture \(ms(done - listed)) ms, total \(ms(done - begin)) ms (VM figures are not measurements)")
            checkDecoys(in: image, screen: screen, index: index)
            if let save = options.save {
                let path = options.repeatCount > 1 ? save.replacingOccurrences(of: ".png", with: "-\(index).png") : save
                do {
                    try Self.writePNG(image, to: path)
                    log("#\(index) saved \(path)")
                } catch {
                    log("#\(index) save failed: \(error.localizedDescription)")
                }
            }
        } catch {
            log("#\(index) capture failed: \(error.localizedDescription) [\((error as NSError).code)]")
        }
    }

    private func configuration(for display: SCDisplay) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = Self.screenUnderPointer()?.backingScaleFactor ?? 2
        var width = Double(display.width) * scale
        var height = Double(display.height) * scale
        let longSide = max(width, height)
        if longSide > 4096 {
            width *= 4096 / longSide
            height *= 4096 / longSide
        }
        config.width = Int(width.rounded())
        config.height = Int(height.rounded())
        config.showsCursor = false
        config.capturesAudio = false
        return config
    }

    private func showDecoys() {
        guard let screen = Self.screenUnderPointer() else { return }
        let frame = screen.visibleFrame
        let size = NSSize(width: 360, height: 220)
        let specs: [(String, NSColor, NSWindow.Level, Bool)] = [
            ("palette-like", NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1), paletteLevel, true),
            ("menu-like", NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1), paletteLevel, true),
            ("hud-like", NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1), paletteLevel, false),
        ]
        for (offset, spec) in specs.enumerated() {
            let origin = NSPoint(
                x: frame.minX + 80 + CGFloat(offset) * (size.width + 40), y: frame.midY - size.height / 2)
            let panel = NSPanel(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered, defer: false)
            panel.isFloatingPanel = spec.3
            panel.level = spec.2
            panel.isOpaque = true
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = !spec.3
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = spec.1
            panel.orderFrontRegardless()
            if spec.0 == "menu-like", let palette = decoyWindows.first?.window {
                palette.addChildWindow(panel, ordered: .above)
            }
            decoyWindows.append(Decoy(name: spec.0, color: spec.1, window: panel))
        }
        log("decoys shown: \(decoyWindows.map { "\($0.name)#\($0.window.windowNumber)" })")
    }

    private func checkDecoys(in image: CGImage, screen: NSScreen, index: Int) {
        guard !decoyWindows.isEmpty, let pixels = RGBAImage(image) else { return }
        let sx = Double(image.width) / screen.frame.width
        let sy = Double(image.height) / screen.frame.height
        for decoy in decoyWindows {
            let rect = decoy.window.frame.insetBy(dx: 40, dy: 40)
            let px = Int((rect.minX - screen.frame.minX) * sx)
            let py = Int((screen.frame.maxY - rect.maxY) * sy)
            let match = pixels.fraction(
                matching: decoy.color, x: px, y: py, width: Int(rect.width * sx), height: Int(rect.height * sy))
            let verdict = match > 0.5 ? "VISIBLE in image" : "absent from image"
            log("#\(index) decoy \(decoy.name): \(verdict) (\(Int(match * 100))% of its pixels match)")
        }
    }

    private func ms(_ duration: Duration) -> Int {
        Int(Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)
    }

    private func log(_ line: String) {
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        FileHandle.standardError.write(Data(stamped.utf8))
        let url = URL(fileURLWithPath: options.report)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: url)
        }
    }

    static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    static func cdhash() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
            let dict = info as? [String: Any], let hash = dict[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func writePNG(_ image: CGImage, to path: String) throws {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: path))
    }
}

// Spotcast's own `.palette` level (Platform/WindowLevel.swift), which PalettePanel and HUDPanel use.
let paletteLevel = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)

struct Decoy {
    let name: String
    let color: NSColor
    let window: NSPanel
}

struct RGBAImage {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        bytes = buffer
    }

    func fraction(matching color: NSColor, x: Int, y: Int, width w: Int, height h: Int) -> Double {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        let target = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int($0 * 255) }
        var hits = 0
        var total = 0
        for row in stride(from: max(0, y), to: min(height, y + h), by: 4) {
            for col in stride(from: max(0, x), to: min(width, x + w), by: 4) {
                let offset = (row * width + col) * 4
                total += 1
                let close = (0..<3).allSatisfy { abs(Int(bytes[offset + $0]) - target[$0]) < 48 }
                if close { hits += 1 }
            }
        }
        return total == 0 ? 0 : Double(hits) / Double(total)
    }
}
