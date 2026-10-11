import Foundation

/// Shared request body / SSE decoding for Responses-API-shaped backends:
/// the ChatGPT codex backend and xAI's cli-chat-proxy.
public enum ResponsesWire {

    /// Builds the streaming Responses request body.
    /// - `store: false` and `stream: true` are required by the codex backend.
    /// - The rendered prompt travels as a single `user` input message.
    public static func bodyData(model: String,
                                instructions: String?,
                                prompt: String,
                                include: [String]? = nil) throws -> Data {
        let body = Body(
            model: model,
            instructions: instructions,
            input: [
                InputItem(type: "message",
                          role: "user",
                          content: [ContentItem(type: "input_text", text: prompt)])
            ],
            stream: true,
            store: false,
            include: include
        )
        return try JSONEncoder().encode(body)
    }

    /// Decodes one SSE event (name + data payload) into stream events.
    public static func decode(eventName: String?, data: String) -> [LLMStreamEvent] {
        guard let jsonData = data.data(using: .utf8),
              let payload = try? JSONDecoder().decode(EventPayload.self, from: jsonData) else {
            return []
        }
        let type = payload.type ?? eventName ?? ""
        switch type {
        case "response.output_text.delta":
            if let delta = payload.delta, !delta.isEmpty {
                return [.delta(delta)]
            }
            return []
        case "response.completed":
            return [.done]
        case "response.failed", "response.incomplete", "error":
            let message = payload.response?.error?.message
                ?? payload.error?.message
                ?? payload.message
                ?? "The model reported a failure (\(type))."
            return [.failed(message)]
        default:
            return [] // created / in_progress / reasoning / item events: ignored
        }
    }

    // MARK: - Wire structs

    struct ContentItem: Encodable {
        let type: String
        let text: String
    }

    struct InputItem: Encodable {
        let type: String
        let role: String
        let content: [ContentItem]
    }

    struct Body: Encodable {
        let model: String
        let instructions: String?
        let input: [InputItem]
        let stream: Bool
        let store: Bool
        let include: [String]?
    }

    private struct EventPayload: Decodable {
        struct ResponseObject: Decodable {
            struct ResponseError: Decodable {
                let message: String?
            }
            let error: ResponseError?
        }
        struct TopLevelError: Decodable {
            let message: String?
        }
        let type: String?
        let delta: String?
        let response: ResponseObject?
        let error: TopLevelError?
        let message: String?
    }
}
