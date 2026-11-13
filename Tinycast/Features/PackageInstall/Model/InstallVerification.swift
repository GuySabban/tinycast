import Foundation

/// Whether a `brew` run that exited 0 really left a working, signed app behind.
enum InstallVerification: Sendable, Equatable {
    /// Gathered off the main actor by `InstallVerifier`, after `brew` exits.
    struct Observation: Sendable, Equatable {
        let hasCaskroomEntry: Bool
        let missingApps: [String]
        let unsignedApps: [String]
    }

    case verified
    case noCaskroomEntry
    case appMissing(String)
    case appNotDeveloperIDSigned(String)

    /// The first failed check, in the order a user can act on: record, presence, signature.
    static func judge(_ observation: Observation) -> InstallVerification {
        guard observation.hasCaskroomEntry else { return .noCaskroomEntry }
        if let app = observation.missingApps.first { return .appMissing(app) }
        if let app = observation.unsignedApps.first { return .appNotDeveloperIDSigned(app) }
        return .verified
    }
}
