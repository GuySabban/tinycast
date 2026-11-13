import Foundation

/// Gathers what `InstallVerification` judges, after `brew` exits 0.
enum InstallVerifier {
    /// Off the main actor: a strict seal check walks every nested bundle of a large app.
    @concurrent
    nonisolated static func observe(
        record: CaskRecord, prefix: URL = HomebrewEnvironment.prefix, home: String = NSHomeDirectory()
    ) async -> InstallVerification.Observation {
        let caskroomEntry = prefix.appending(path: "Caskroom/\(record.token)/.metadata")
        var missing: [String] = []
        var unsigned: [String] = []
        for app in record.apps {
            let path = app.path(home: home)
            guard FileManager.default.fileExists(atPath: path) else {
                missing.append(app.installedName)
                continue
            }
            if BundleSignature.trustedHash(of: URL(fileURLWithPath: path), releaseSigned: true) == nil {
                unsigned.append(app.installedName)
            }
        }
        return InstallVerification.Observation(
            hasCaskroomEntry: FileManager.default.fileExists(atPath: caskroomEntry.path(percentEncoded: false)),
            missingApps: missing, unsignedApps: unsigned)
    }
}
