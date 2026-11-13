import Foundation

/// A Homebrew cask's name, as the one piece of outside text that reaches `brew` as an argument.
enum CaskToken {
    /// `^[a-z0-9][a-z0-9@+._-]*$`: no space, quote or leading dash a shell or `brew` could misread.
    static func isValid(_ token: String) -> Bool {
        guard let first = token.utf8.first, isLowercaseOrDigit(first) else { return false }
        return token.utf8.dropFirst().allSatisfy { isLowercaseOrDigit($0) || punctuation.contains($0) }
    }

    private static let punctuation: Set<UInt8> = Set("@+._-".utf8)

    private static func isLowercaseOrDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
