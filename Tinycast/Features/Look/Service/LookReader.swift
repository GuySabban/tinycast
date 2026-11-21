import CoreGraphics
import Foundation

/// Captures, reads and detects for one Look at a time; a newer Look or a cancel drops the older one.
@MainActor
final class LookReader {
    struct Reading: Sendable {
        /// Kept by whoever shows the Look, for Ask AI on Codex, and dropped when it closes.
        let image: CGImage
        let text: String
        let items: [LookItem]
    }

    enum Outcome: Sendable {
        case read(Reading)
        case notPermitted
        case failed
    }

    struct Steps: Sendable {
        var isPermitted: @Sendable () -> Bool
        var requestPermission: @Sendable () -> Void
        var capture: @Sendable (CGDirectDisplayID) async throws -> CGImage
        var encode: @Sendable (CGImage) throws -> Data
        var recognize: @Sendable (consuming Data, Duration) async throws -> String
        var detect: @Sendable (String) -> [LookItem]
        var now: @Sendable () -> ContinuousClock.Instant
    }

    private let steps: Steps
    private(set) var deadline: LookRecognitionDeadline
    private var task: Task<Void, Never>?
    private var generation = 0
    private var hasRequested = false

    init(steps: Steps = .live, deadline: LookRecognitionDeadline = LookRecognitionDeadline()) {
        self.steps = steps
        self.deadline = deadline
    }

    var isReading: Bool { task != nil }

    func start(on display: CGDirectDisplayID, deliver: @escaping @MainActor (Outcome) -> Void) {
        cancel()
        let look = generation
        // Once per launch: macOS prompts only while undecided; the row explains a refusal.
        if !hasRequested, !steps.isPermitted() {
            hasRequested = true
            steps.requestPermission()
        }
        let steps = steps
        let limit = deadline.limit(at: steps.now())
        task = Task {
            let (outcome, recognition) = await Self.read(display, steps: steps, limit: limit)
            if let recognition { deadline.record(recognition, at: steps.now()) }
            guard look == generation, !Task.isCancelled else { return }
            task = nil
            deliver(outcome)
        }
    }

    /// Ends the helper through the worker's cancellation; nothing of this Look is delivered after.
    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    @concurrent
    private nonisolated static func read(
        _ display: CGDirectDisplayID, steps: Steps, limit: Duration
    ) async -> (Outcome, LookRecognitionDeadline.Outcome?) {
        let image: CGImage
        do {
            image = try await Signposts.interval("Look.capture") { try await steps.capture(display) }
        } catch {
            // A grant works before preflight says so, so only a failed capture counts as refused.
            return (steps.isPermitted() ? .failed : .notPermitted, nil)
        }
        let started = steps.now()
        let text: String
        do {
            text = try await Signposts.interval("Look.recognize") {
                try await recognize(image, steps: steps, limit: limit)
            }
        } catch {
            if Task.isCancelled { return (.failed, .cancelled) }
            return (.failed, steps.now() - started >= limit ? .timedOut : .failed)
        }
        if Task.isCancelled { return (.failed, .recognized) }
        let items = Signposts.interval("Look.detect") { steps.detect(text) }
        return (.read(Reading(image: image, text: text, items: items)), .recognized)
    }

    /// Hands the PNG on, so it is freed once the helper has read it rather than when the Look closes.
    private nonisolated static func recognize(
        _ image: CGImage, steps: Steps, limit: Duration
    ) async throws -> String {
        let png = try steps.encode(image)
        try Task.checkCancellation()
        return try await steps.recognize(consume png, limit)
    }
}

extension LookReader.Steps {
    static let live = LookReader.Steps(
        isPermitted: { ScreenRecordingPermission.isGranted() },
        requestPermission: { ScreenRecordingPermission.request() },
        capture: { try await ScreenCapturer.capture(display: $0) },
        encode: { try ScreenCapturer.png($0) },
        recognize: { png, limit in
            try await ClipboardTextWorker.extract(
                imageData: consume png, executable: ClipboardTextWorker.executable, timeout: limit)
        },
        // The system clock, as the detector itself reads it (D44).
        detect: { LookDetector.items(in: $0, now: Date(), calendar: .current) },
        now: { ContinuousClock.now })
}
