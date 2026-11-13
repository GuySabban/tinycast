import Foundation
import Security

/// Gathers what `InstallVerification` judges, after `brew` exits 0.
enum InstallVerifier {
    /// Apple's own seal or any Developer ID; an ad-hoc or broken seal fails both.
    nonisolated static let trustedSigner = "anchor apple or (\(BundleSignature.developerID))"

    /// Off the main actor: a strict seal check walks every nested bundle of a large app.
    @concurrent
    nonisolated static func observe(
        record: CaskRecord, prefix: URL = HomebrewEnvironment.prefix, home: String = NSHomeDirectory()
    ) async -> InstallVerification.Observation {
        let caskroomEntry = prefix.appending(path: "Caskroom/\(record.token)/.metadata")
        var missing: [String] = []
        var untrusted: [String] = []
        for app in record.apps {
            let path = app.path(home: home)
            guard FileManager.default.fileExists(atPath: path) else {
                missing.append(app.installedName)
                continue
            }
            if !isTrusted(URL(fileURLWithPath: path)) { untrusted.append(app.installedName) }
        }
        return InstallVerification.Observation(
            hasCaskroomEntry: FileManager.default.fileExists(atPath: caskroomEntry.path(percentEncoded: false)),
            missingApps: missing, untrustedApps: untrusted)
    }

    /// The same strict, nested check `BundleSignature` runs on an update, against a wider signer.
    private nonisolated static func isTrusted(_ bundle: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
            SecRequirementCreateWithString(trustedSigner as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }
}
