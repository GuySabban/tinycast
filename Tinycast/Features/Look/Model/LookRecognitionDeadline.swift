import Foundation

/// How long one Look waits for text: Vision's first read after a while has taken 45 to 75 s.
struct LookRecognitionDeadline: Sendable, Equatable {
    enum Outcome: Sendable { case recognized, timedOut, failed, cancelled }

    static let warmLimit = Duration.seconds(5)
    static let coldLimit = Duration.seconds(120)
    /// A guess at how long Vision stays loaded; past it, the next Look waits as the first one does.
    static let staysWarm = Duration.seconds(15 * 60)

    private var lastRead: ContinuousClock.Instant?

    func limit(at now: ContinuousClock.Instant) -> Duration {
        guard let lastRead, now - lastRead < Self.staysWarm else { return Self.coldLimit }
        return Self.warmLimit
    }

    /// Only a read proves Vision is loaded, and a timeout says it may have been dropped again.
    mutating func record(_ outcome: Outcome, at now: ContinuousClock.Instant) {
        switch outcome {
        case .recognized: lastRead = now
        case .timedOut: lastRead = nil
        case .failed, .cancelled: break
        }
    }
}
