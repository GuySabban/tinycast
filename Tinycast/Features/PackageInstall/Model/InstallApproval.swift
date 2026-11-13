import Foundation

/// The approval dialog's message: every value from the record, and the exact command.
enum InstallApproval {
    static func message(record: CaskRecord, invocation: BrewInvocation) -> String {
        var lines = [heading(record)]
        let cask = String(localized: "Homebrew cask “\(record.token)”")
        lines.append(
            record.homepage.flatMap(host).map { String(localized: "Source: \($0), \(cask)") }
                ?? String(localized: "Source: \(cask)"))
        if let download = record.downloadURL.flatMap(host) {
            lines.append(String(localized: "Download from: \(download)"))
        }
        lines.append(String(localized: "Runs: \(invocation.displayText)"))
        if !record.apps.isEmpty {
            let targets = record.apps.map(\.target).joined(separator: ", ")
            lines.append(String(localized: "Installs to: \(targets)"))
        }
        if let deprecated = record.deprecated {
            lines.append(deprecation(deprecated))
        }
        return lines.joined(separator: "\n")
    }

    /// "Blender 5.3.0 · 3D creation suite", dropping whatever the record lacks.
    private static func heading(_ record: CaskRecord) -> String {
        let name = [record.displayName, record.displayVersion].compactMap(\.self).joined(separator: " ")
        return [name, record.summary].compactMap(\.self).joined(separator: " · ")
    }

    private static func host(_ url: URL) -> String? {
        guard let host = url.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func deprecation(_ retirement: CaskRecord.Retirement) -> String {
        let reason = retirement.reason?.sentence ?? ""
        guard let replacement = retirement.replacementCask else {
            return String(localized: "Homebrew has deprecated this cask. \(reason)")
        }
        return String(localized: "Homebrew has deprecated this cask. \(reason) Use “\(replacement)” instead.")
    }
}
