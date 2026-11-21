import Foundation

/// A detected date as an event editor would open it.
struct LookDate: Sendable, Hashable {
    let start: Date
    let duration: TimeInterval
    /// False for a date written without a time, which starts at 09:00.
    let hasTime: Bool
    /// True for a time written without a day, placed on its next occurrence (D42).
    let dayIsGuessed: Bool
}
