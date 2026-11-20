import CoreText
import Foundation
import ImageIO

/// Look's recognition from memory: PNG bytes through the real `ClipboardTextHelper` built from source.
@main
@MainActor
struct LookRecognitionTests {
    static var failures = 0
    static var passes = 0
    /// No other harness draws this size, so a file of it in a temporary directory is ours.
    static let fixtureSize = (width: 1234, height: 321)

    static func main() async throws {
        let build = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-look-recognition-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: build) }
        let helper = try buildHelper(into: build)

        let page = makeCanvas(width: fixtureSize.width, height: fixtureSize.height)
        draw("ALPINE RECEIPT 7391", in: page)
        let png = pngData(page.makeImage()!)

        let before = snapshot(excluding: build)
        let text = try await ClipboardTextWorker.extract(imageData: png, executable: helper, timeout: .seconds(60))
        expect(text.contains("ALPINE RECEIPT 7391"), "PNG bytes through the helper are recognized")
        let leaks = writtenImages(since: before, excluding: build, matching: png)
        expect(leaks.isEmpty, "nothing is written under the temporary directory: \(leaks)")

        let control = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-look-control-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: control) }
        let controlBefore = snapshot(excluding: build)
        try png.write(to: control)
        let fileText = try await ClipboardTextWorker.extract(at: control, isPDF: false, executable: helper)
        expect(fileText.contains("ALPINE RECEIPT 7391"), "the file mode still recognizes")
        expect(
            writtenImages(since: controlBefore, excluding: build, matching: png) == [control.resolvingSymlinksInPath().path],
            "the leak check sees an image written under the temporary directory")

        let screen = makeCanvas(width: 5120, height: 2880)
        draw("THIRTEEN POINT LINE 4417", in: screen, at: CGPoint(x: 200, y: 2000), size: 26)
        draw("ELEVEN POINT LINE 8263", in: screen, at: CGPoint(x: 200, y: 1400), size: 22)
        let screenPNG = pngData(screen.makeImage()!)
        expect(screenPNG.count > 65_536, "the 5K page outgrows a pipe buffer")
        let screenText = try await ClipboardTextWorker.extract(
            imageData: screenPNG, executable: helper, timeout: .seconds(60))
        expect(screenText.contains("4417"), "13-point text on a 5K page is read")
        expect(screenText.contains("8263"), "11-point text on a 5K page is read")

        await expectFailure("garbage bytes fail") {
            try await ClipboardTextWorker.extract(
                imageData: Data("not a png".utf8), executable: helper, timeout: .seconds(60))
        }
        await expectFailure("empty input fails") {
            try await ClipboardTextWorker.extract(imageData: Data(), executable: helper, timeout: .seconds(60))
        }
        await expectFailure("a helper that never reads fails instead of raising SIGPIPE") {
            try await ClipboardTextWorker.extract(
                imageData: Data(count: 4_000_000), executable: URL(fileURLWithPath: "/usr/bin/false"),
                timeout: .seconds(60))
        }
        await expectFailure("the deadline stops a slow recognition") {
            try await ClipboardTextWorker.extract(
                imageData: screenPNG, executable: helper, timeout: .milliseconds(50))
        }
        expect(try await helperGone(helper), "a helper past its deadline is reaped")

        let cancelled = Task.detached {
            try await ClipboardTextWorker.extract(imageData: screenPNG, executable: helper, timeout: .seconds(60))
        }
        try await Task.sleep(for: .milliseconds(100))
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            expect(false, "cancelled recognition throws")
        } catch is CancellationError { expect(true, "cancelled recognition throws") }
        expect(try await helperGone(helper), "a cancelled helper is gone within 1 s")

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func buildHelper(into directory: URL) throws -> URL {
        let helper = directory.appendingPathComponent("ClipboardTextHelper")
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = [
            "swiftc", "-swift-version", "6", "-O",
            "Tinycast/Features/Clipboard/Service/ClipboardTextExtractor.swift",
            "Tinycast/Features/Clipboard/Service/ClipboardTextHelper.swift", "-o", helper.path
        ]
        try compile.runObservingExit().wait()
        guard compile.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
        return helper
    }

    /// The temporary roots a helper inherits, by path, with each regular file's size and date.
    static func snapshot(excluding build: URL) -> [String: [AnyHashable]] {
        let roots = Set(
            [FileManager.default.temporaryDirectory, URL(fileURLWithPath: "/tmp")]
                .map { $0.resolvingSymlinksInPath() })
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let skipped = build.resolvingSymlinksInPath().path
        var files: [String: [AnyHashable]] = [:]
        for root in roots {
            guard
                let walk = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: keys, errorHandler: { _, _ in true })
            else { continue }
            for case let url as URL in walk {
                let path = url.resolvingSymlinksInPath().path
                if path.hasPrefix(skipped) { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
                else { continue }
                files[path] = [values.fileSize ?? 0, values.contentModificationDate ?? .distantPast]
            }
        }
        return files
    }

    /// Other harnesses write to the same directories in parallel, so only our fixture counts.
    static func writtenImages(
        since before: [String: [AnyHashable]], excluding build: URL, matching png: Data
    ) -> [String] {
        snapshot(excluding: build).filter { before[$0.key] != $0.value }.keys.filter { path in
            let url = URL(fileURLWithPath: path)
            if (try? Data(contentsOf: url)) == png { return true }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else { return false }
            return properties[kCGImagePropertyPixelWidth] as? Int == fixtureSize.width
                && properties[kCGImagePropertyPixelHeight] as? Int == fixtureSize.height
        }.sorted()
    }

    static func helperGone(_ helper: URL) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            let search = Process()
            search.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            search.arguments = ["-f", helper.path]
            search.standardOutput = FileHandle.nullDevice
            try search.runObservingExit().wait()
            if search.terminationStatus == 1 { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    static func expectFailure(_ message: String, _ body: @Sendable () async throws -> String) async {
        do {
            _ = try await body()
            expect(false, message)
        } catch ClipboardTextWorker.Failure.recognition {
            expect(true, message)
        } catch {
            expect(false, "\(message): \(error)")
        }
    }

    static func makeCanvas(width: Int, height: Int) -> CGContext {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    static func pngData(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        expect(CGImageDestinationFinalize(destination), "encode PNG in memory")
        return data as Data
    }

    static func draw(
        _ text: String, in context: CGContext, at origin: CGPoint = CGPoint(x: 40, y: 150),
        size: CGFloat = 48
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                "Helvetica" as CFString, size, nil)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = origin
        CTLineDraw(line, context)
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}
