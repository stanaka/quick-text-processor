import Foundation

/// One event of a streaming LLM response.
public enum LLMStreamEvent: Equatable, Sendable {
    /// A chunk of output text.
    case delta(String)
    /// The response finished successfully.
    case done
    /// The backend reported a failure mid-stream.
    case failed(String)
}

public enum LLMError: Error, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case notSignedIn(String)
    case http(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        case .notSignedIn(let message):
            return message
        case .http(let status, let message):
            return "HTTP \(status): \(message)"
        }
    }
}

/// A configured LLM endpoint the pipeline can stream from.
public protocol LLMClient: Sendable {
    var providerName: String { get }
    var modelName: String { get }
    /// Starts the request eagerly (so HTTP errors throw here) and returns the
    /// event stream. The stream ends after `.done` / `.failed`.
    func stream(prompt: String) async throws -> AsyncThrowingStream<LLMStreamEvent, Error>
}
