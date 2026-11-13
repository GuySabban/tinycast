import Foundation

/// Homebrew's public JSON API: one cask's record, fetched on Return, never while typing.
enum CaskAPI {
    enum Failure: Error, Equatable {
        /// Homebrew has no such cask now, as for a token renamed since the index was fetched.
        case notFound
        case unavailable
        case malformed
    }

    nonisolated static let base = URL(string: "https://formulae.brew.sh/api/")!

    /// Cacheless, never `URLSession.shared`, so nothing Homebrew sends is kept on disk.
    nonisolated static func session(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.protocolClasses = protocolClasses
        return URLSession(configuration: configuration)
    }

    /// Throws `Failure`, or `CancellationError` when the caller's task is cancelled.
    @concurrent
    nonisolated static func record(
        token: String, variation: String?, baseURL: URL = base, session: URLSession
    ) async throws -> CaskRecord {
        guard CaskToken.isValid(token) else { throw Failure.notFound }
        let request = URLRequest(url: baseURL.appending(path: "cask/\(token).json"), timeoutInterval: 10)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try Task.checkCancellation()
            throw Failure.unavailable
        }
        try Task.checkCancellation()
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 404: throw Failure.notFound
        default: throw Failure.unavailable
        }
        guard let record = try? CaskRecord.decode(data, variation: variation), record.token == token else {
            throw Failure.malformed
        }
        return record
    }
}
