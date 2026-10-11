import Foundation

/// Request building and stream decoding for OpenAI-compatible
/// `/v1/chat/completions` endpoints (OpenAI, xAI api.x.ai, Ollama, LM Studio,
/// vLLM, OpenRouter, ...).
public enum OpenAICompatWire {

    /// Normalizes a user-entered base URL to the chat-completions endpoint.
    /// Accepts "https://host", "https://host/", "https://host/v1",
    /// "https://host/v1/" — all yield ".../v1/chat/completions".
    public static func chatCompletionsURL(base: String) -> URL? {
        guard let v1 = normalizedV1Base(base) else { return nil }
        return URL(string: v1 + "/chat/completions")
    }

    /// Normalizes a user-entered base URL to the model-listing endpoint
    /// (".../v1/models"), using the same rules as `chatCompletionsURL`.
    public static func modelsURL(base: String) -> URL? {
        guard let v1 = normalizedV1Base(base) else { return nil }
        return URL(string: v1 + "/models")
    }

    /// "https://host[/…]" → "https://host/v1"; nil when blank.
    private static func normalizedV1Base(_ base: String) -> String? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if !trimmed.hasSuffix("/v1") {
            trimmed += "/v1"
        }
        return trimmed
    }

    public static func request(baseURL: String,
                               apiKey: String,
                               model: String,
                               prompt: String) throws -> URLRequest {
        guard let url = chatCompletionsURL(base: baseURL) else {
            throw LLMError.invalidConfiguration("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            ChatBody(model: model,
                     messages: [.init(role: "user", content: prompt)],
                     stream: true)
        )
        request.timeoutInterval = 300
        return request
    }

    /// GET {base}/v1/models — lists the models the endpoint serves.
    /// An empty API key omits the Authorization header (Ollama, LM Studio).
    public static func modelsRequest(baseURL: String, apiKey: String) throws -> URLRequest {
        guard let url = modelsURL(base: baseURL) else {
            throw LLMError.invalidConfiguration("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30
        return request
    }

    /// Decodes a GET /v1/models response ({"data":[{"id":...}]}) into a sorted,
    /// de-duplicated list of model ids. Unknown shapes yield [].
    public static func modelIDs(fromModelsResponse data: Data) -> [String] {
        guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return []
        }
        let ids = (response.data ?? []).compactMap(\.id).filter { !$0.isEmpty }
        return Array(Set(ids)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Decodes one SSE `data:` payload into stream events.
    public static func decode(data: String) -> [LLMStreamEvent] {
        if data == "[DONE]" {
            return [.done]
        }
        guard let jsonData = data.data(using: .utf8) else { return [] }
        if let chunk = try? JSONDecoder().decode(ChatChunk.self, from: jsonData) {
            if let message = chunk.error?.message {
                return [.failed(message)]
            }
            var events: [LLMStreamEvent] = []
            if let choice = chunk.choices?.first {
                if let content = choice.delta?.content, !content.isEmpty {
                    events.append(.delta(content))
                }
                if choice.finish_reason != nil {
                    events.append(.done)
                }
            }
            return events
        }
        return []
    }

    /// Human-readable message for a non-200 response.
    public static func errorMessage(status: Int, body: Data) -> String {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body),
           let message = envelope.error?.message ?? envelope.message {
            return message
        }
        if let text = String(data: body, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(text.prefix(500))
        }
        return HTTPURLResponse.localizedString(forStatusCode: status)
    }

    // MARK: - Wire structs

    private struct ChatBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        let stream: Bool
    }

    private struct ModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String?
        }
        let data: [Model]?
    }

    private struct ChatChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta?
            let finish_reason: String?
        }
        struct APIError: Decodable {
            let message: String?
        }
        let choices: [Choice]?
        let error: APIError?
    }

    struct ErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String?
        }
        let error: APIError?
        let message: String?
    }
}
