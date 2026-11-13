import Foundation

/// Recognises "install NAME" in the launcher's query. The keyword is Homebrew's, so not localized.
enum InstallIntent {
    static let keyword = "install"

    /// "install blender" gives "blender"; nil unless the query is an install request with a name.
    static func name(in query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gap = trimmed.firstIndex(where: \.isWhitespace),
            trimmed[..<gap].lowercased() == keyword
        else { return nil }
        let name = trimmed[gap...].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
