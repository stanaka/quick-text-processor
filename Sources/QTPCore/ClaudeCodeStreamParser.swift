import Foundation

/// Incremental decoder for Claude Code's newline-delimited JSON output.
public struct ClaudeCodeStreamParser {
    private var buffer = Data()
    private var emittedText = false
    public private(set) var resultReceived = false
    public private(set) var failure: String?

    public init() {}

    public mutating func feed(_ data: Data) throws -> [LLMStreamEvent] {
        buffer.append(data)
        var events: [LLMStreamEvent] = []
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            events += try decode(line)
        }
        guard buffer.count <= 16 * 1024 * 1024 else {
            throw LLMError.invalidConfiguration("Claude Code output line exceeded 16 MB.")
        }
        return events
    }

    public mutating func finish() throws -> [LLMStreamEvent] {
        let remaining = buffer
        buffer.removeAll()
        return try decode(remaining)
    }

    private mutating func decode(_ line: Data) throws -> [LLMStreamEvent] {
        if line.allSatisfy({ $0 == 13 || $0 == 32 || $0 == 9 }) { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String else {
            throw LLMError.invalidConfiguration("Invalid JSON event from Claude Code. Update Claude Code and try again.")
        }
        if resultReceived { return [] }
        if type == "result" {
            resultReceived = true
            if object["is_error"] as? Bool == true || object["subtype"] as? String != "success" {
                let errors = (object["errors"] as? [String])?.joined(separator: "\n")
                failure = errors ?? (object["result"] as? String) ?? "Claude Code failed to complete the request."
                return []
            }
            if !emittedText, let text = object["result"] as? String, !text.isEmpty {
                emittedText = true
                return [.delta(text)]
            }
        }
        guard type == "stream_event", object["parent_tool_use_id"] == nil || object["parent_tool_use_id"] is NSNull,
              let event = object["event"] as? [String: Any],
              event["type"] as? String == "content_block_delta",
              let delta = event["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta",
              let text = delta["text"] as? String else { return [] }
        emittedText = true
        return [.delta(text)]
    }
}
