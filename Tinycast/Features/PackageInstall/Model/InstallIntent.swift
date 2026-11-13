import Foundation

/// Recognises "install NAME" in the launcher's query. The keyword is Homebrew's, so not localized.
enum InstallIntent {
    static let keyword = "install"
    /// One letter matches hundreds of casks, so a shorter name is not a request yet.
    static let minimumLetters = 2

    /// "install blender" gives "blender"; nil unless the query is an install request with a name.
    static func name(in query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gap = trimmed.firstIndex(where: \.isWhitespace),
            trimmed[..<gap].lowercased() == keyword
        else { return nil }
        let name = trimmed[gap...].trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = name.lazy.filter { $0.isLetter || $0.isNumber }.prefix(minimumLetters).count
        return letters < minimumLetters ? nil : name
    }
}
