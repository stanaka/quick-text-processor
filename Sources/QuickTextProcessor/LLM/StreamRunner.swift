import Foundation
import QTPCore

enum StreamKind: Sendable {
    case chatCompletions
    case responses
}

/// Runs one streaming LLM HTTP request.
///
/// The request is issued eagerly so HTTP-level failures (401, 429, ...) throw
/// from `start` — callers can react (e.g. refresh OAuth tokens and retry)
/// before any stream is handed to the UI.
enum StreamRunner {

    static func start(request: URLRequest,
                      kind: StreamKind,
                      session: URLSession = .shared) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.http(status: -1, message: "Unexpected non-HTTP response")
        }
        guard http.statusCode == 200 else {
            var body = Data()
            do {
                for try await byte in bytes {
                    body.append(byte)
                    if body.count > 64 * 1024 { break }
                }
            } catch {
                // Partial error bodies are fine.
            }
            throw LLMError.http(status: http.statusCode,
                                message: OpenAICompatWire.errorMessage(status: http.statusCode, body: body))
        }

        return AsyncThrowingStream { continuation in
            let pump = Task {
                var parser = SSEParser()
                var finished = false

                func emit(_ sseEvents: [SSEParser.Event]) {
                    for sseEvent in sseEvents where !finished {
                        let decoded: [LLMStreamEvent]
                        switch kind {
                        case .chatCompletions:
                            decoded = OpenAICompatWire.decode(data: sseEvent.data)
                        case .responses:
                            decoded = ResponsesWire.decode(eventName: sseEvent.event, data: sseEvent.data)
                        }
                        for event in decoded where !finished {
                            continuation.yield(event)
                            switch event {
                            case .done, .failed:
                                finished = true
                                continuation.finish()
                            case .delta:
                                break
                            }
                        }
                    }
                }

                do {
                    for try await byte in bytes {
                        emit(parser.feed(CollectionOfOne(byte)))
                        if finished { break }
                    }
                    if !finished {
                        // Stream ended without a terminal event; treat as done.
                        continuation.yield(.done)
                        continuation.finish()
                    }
                } catch {
                    if !finished {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in
                pump.cancel()
            }
        }
    }
}
