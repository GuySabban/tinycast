import Foundation

enum WebSearchFailure: Error, Sendable, Equatable {
    case missingKey, offline, unauthorized, outOfCredit, rateLimited, server, malformedReply
    /// Not shown to the user; the session drops it.
    case cancelled

    /// Nil for a success. Exa's 403 is a blocked team or a disabled feature, not a bad key.
    init?(status: Int) {
        switch status {
        case 200...299: return nil
        case 401: self = .unauthorized
        case 402: self = .outOfCredit
        case 429: self = .rateLimited
        default: self = .server
        }
    }

    init(transport error: any Error) {
        let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
        self = cancelled ? .cancelled : .offline
    }
}
