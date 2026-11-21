import CoreGraphics
import Foundation

/// Look's capture-to-items run with stand-in steps: who gets a result, and how long it may wait.
@main
@MainActor
struct LookReaderTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// What the stand-in steps saw, written from whichever thread ran them.
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        private var limits: [Duration] = []

        func add(_ entry: String) { lock.withLock { entries.append(entry) } }
        func add(limit: Duration) { lock.withLock { limits.append(limit) } }
        var all: [String] { lock.withLock { entries } }
        var allLimits: [Duration] { lock.withLock { limits } }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var instant = ContinuousClock.now
        var now: ContinuousClock.Instant { lock.withLock { instant } }
        func advance(_ by: Duration) { lock.withLock { instant += by } }
    }

    enum Stand: Error { case failed, timedOut }

    nonisolated static let image: CGImage = {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    /// Display 1 is slow to capture, so a Look on display 2 started after it finishes first.
    static func steps(
        log: Log, clock: Clock = Clock(), permitted: Bool = true, captureFails: Bool = false,
        recognition: @escaping @Sendable (Duration) async throws -> String = { _ in "Call 555-0100" }
    ) -> LookReader.Steps {
        LookReader.Steps(
            isPermitted: { permitted },
            requestPermission: { log.add("request") },
            capture: { display in
                log.add("capture \(display)")
                if display == 1 { try await Task.sleep(for: .milliseconds(300)) }
                if captureFails { throw Stand.failed }
                return image
            },
            encode: { _ in Data([0x89, 0x50, 0x4E, 0x47]) },
            recognize: { png, limit in
                log.add("recognize \(png.count)")
                log.add(limit: limit)
                return try await recognition(limit)
            },
            detect: { text in
                LookDetector.items(in: text, now: Date(timeIntervalSince1970: 0), calendar: .current)
            },
            now: { clock.now })
    }

    static func settle(_ reader: LookReader) async {
        for _ in 0..<200 where reader.isReading { try? await Task.sleep(for: .milliseconds(10)) }
        try? await Task.sleep(for: .milliseconds(50))
    }

    static func main() async {
        await deliversTheReading()
        await newerLookDropsTheOlder()
        await cancelDeliversNothing()
        await firstLookWaitsLonger()
        await timeoutGoesColdAgain()
        await pngFreedOnceTheHelperReadIt()
        await asksForPermissionOnce()
        await refusalNeedsAFailedCapture()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func deliversTheReading() async {
        let log = Log()
        let reader = LookReader(steps: steps(log: log))
        var delivered: [LookReader.Outcome] = []
        reader.start(on: 2) { delivered.append($0) }
        await settle(reader)
        guard delivered.count == 1, case .read(let reading) = delivered[0] else {
            return expect(false, "one reading: \(delivered)")
        }
        expect(reading.text == "Call 555-0100", "text kept")
        expect(reading.image.width == 4, "image kept for Ask AI")
        expect(reading.items.contains { if case .phoneNumber = $0.value { true } else { false } }, "items found")
        expect(log.all == ["capture 2", "recognize 4"], "capture then the PNG to the helper: \(log.all)")
        expect(!reader.isReading, "idle after delivering")
    }

    static func newerLookDropsTheOlder() async {
        let log = Log()
        let reader = LookReader(steps: steps(log: log))
        var delivered: [String] = []
        reader.start(on: 1) { _ in delivered.append("first") }
        reader.start(on: 2) { _ in delivered.append("second") }
        await settle(reader)
        try? await Task.sleep(for: .milliseconds(400))
        expect(delivered == ["second"], "only the newer Look is delivered: \(delivered)")
    }

    static func cancelDeliversNothing() async {
        let log = Log()
        let cancelled = Log()
        let reader = LookReader(
            steps: steps(log: log) { _ in
                do { try await Task.sleep(for: .seconds(5)) } catch { cancelled.add("helper ended") }
                throw CancellationError()
            })
        var delivered = 0
        reader.start(on: 2) { _ in delivered += 1 }
        for _ in 0..<100 where !log.all.contains("recognize 4") { try? await Task.sleep(for: .milliseconds(10)) }
        reader.cancel()
        expect(!reader.isReading, "cancel ends the Look at once")
        try? await Task.sleep(for: .milliseconds(200))
        expect(delivered == 0, "a cancelled Look delivers nothing")
        expect(cancelled.all == ["helper ended"], "cancel reaches the recognition")
    }

    static func firstLookWaitsLonger() async {
        let log = Log()
        let clock = Clock()
        let reader = LookReader(steps: steps(log: log, clock: clock))
        reader.start(on: 2) { _ in }
        await settle(reader)
        clock.advance(.seconds(30))
        reader.start(on: 2) { _ in }
        await settle(reader)
        clock.advance(LookRecognitionDeadline.staysWarm)
        reader.start(on: 2) { _ in }
        await settle(reader)
        let expected = [LookRecognitionDeadline.coldLimit, LookRecognitionDeadline.warmLimit,
                        LookRecognitionDeadline.coldLimit]
        expect(log.allLimits == expected, "cold, warm, then cold after idling: \(log.allLimits)")
    }

    static func timeoutGoesColdAgain() async {
        let log = Log()
        let clock = Clock()
        let calls = Log()
        let reader = LookReader(
            steps: steps(log: log, clock: clock) { limit in
                calls.add("call")
                switch calls.all.count {
                case 2: throw Stand.failed
                case 3:
                    clock.advance(limit)
                    throw Stand.timedOut
                default: return "text"
                }
            })
        for _ in 0..<4 {
            reader.start(on: 2) { _ in }
            await settle(reader)
        }
        let cold = LookRecognitionDeadline.coldLimit
        let warm = LookRecognitionDeadline.warmLimit
        expect(log.allLimits == [cold, warm, warm, cold], "a quick failure stays warm, a timeout goes cold: \(log.allLimits)")
    }

    /// The real worker and a helper that reads its input at once, then takes a second to answer.
    static func pngFreedOnceTheHelperReadIt() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper")
        try? "#!/bin/sh\ncat > /dev/null\nsleep 1\nprintf text\n".write(to: helper, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let events = Log()
        let started = ContinuousClock.now
        @Sendable func elapsed() -> String { (ContinuousClock.now - started) < .milliseconds(500) ? "at once" : "late" }
        var live = steps(log: Log())
        live.encode = { _ in
            let count = 4 << 20
            let bytes = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 1)
            return Data(bytesNoCopy: bytes, count: count, deallocator: .custom { pointer, _ in
                events.add("freed \(elapsed())")
                pointer.deallocate()
            })
        }
        live.recognize = { png, limit in
            let text = try await ClipboardTextWorker.extract(imageData: consume png, executable: helper, timeout: limit)
            events.add("answered \(elapsed())")
            return text
        }
        let reader = LookReader(steps: live)
        var text: String?
        reader.start(on: 2) { if case .read(let reading) = $0 { text = reading.text } }
        for _ in 0..<300 where reader.isReading { try? await Task.sleep(for: .milliseconds(10)) }
        expect(text == "text", "the helper's answer is the reading: \(String(describing: text))")
        expect(events.all == ["freed at once", "answered late"], "PNG freed when read, not when the helper exits: \(events.all)")
    }

    static func asksForPermissionOnce() async {
        let log = Log()
        let reader = LookReader(steps: steps(log: log, permitted: false))
        reader.start(on: 2) { _ in }
        await settle(reader)
        reader.start(on: 2) { _ in }
        await settle(reader)
        expect(log.all.filter { $0 == "request" }.count == 1, "asked once per launch: \(log.all)")
        let granted = Log()
        let allowed = LookReader(steps: steps(log: granted))
        allowed.start(on: 2) { _ in }
        await settle(allowed)
        expect(!granted.all.contains("request"), "never asks once granted")
    }

    static func refusalNeedsAFailedCapture() async {
        var outcomes: [String] = []
        for permitted in [false, true] {
            let reader = LookReader(steps: steps(log: Log(), permitted: permitted, captureFails: true))
            reader.start(on: 2) { outcome in
                if case .notPermitted = outcome { outcomes.append("notPermitted") }
                if case .failed = outcome { outcomes.append("failed") }
            }
            await settle(reader)
        }
        expect(outcomes == ["notPermitted", "failed"], "refused only while preflight is false: \(outcomes)")
        let log = Log()
        var read = false
        let stale = LookReader(steps: steps(log: log, permitted: false))
        stale.start(on: 2) { if case .read = $0 { read = true } }
        await settle(stale)
        expect(read, "a capture that works is used even while preflight still says no")
    }
}
