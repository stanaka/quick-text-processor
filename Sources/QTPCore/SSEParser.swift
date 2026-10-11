import Foundation

/// Incremental parser for text/event-stream (Server-Sent Events).
///
/// Fed raw bytes (so it never depends on how the transport chunks or splits
/// lines) and emits complete events. Handles LF and CRLF, multiple `data:`
/// lines per event (joined with "\n"), `event:` names, and `:` comments /
/// keep-alives. UTF-8 is decoded per line; multi-byte characters can never
/// contain a newline byte, so line splitting is UTF-8 safe.
public struct SSEParser {

    public struct Event: Equatable, Sendable {
        public var event: String?
        public var data: String

        public init(event: String? = nil, data: String) {
            self.event = event
            self.data = data
        }
    }

    private var lineBuffer: [UInt8] = []
    private var dataLines: [String] = []
    private var eventName: String?

    public init() {}

    /// Feed a chunk of bytes; returns every event completed by this chunk.
    public mutating func feed<S: Sequence>(_ chunk: S) -> [Event] where S.Element == UInt8 {
        var events: [Event] = []
        for byte in chunk {
            if byte == 0x0A { // "\n"
                if let event = lineCompleted() {
                    events.append(event)
                }
            } else {
                lineBuffer.append(byte)
            }
        }
        return events
    }

    /// Feed a single already-split line (no trailing newline). Used by tests.
    public mutating func feed(line: String) -> Event? {
        lineBuffer = Array(line.utf8)
        return lineCompleted()
    }

    private mutating func lineCompleted() -> Event? {
        if lineBuffer.last == 0x0D { // strip "\r" of CRLF
            lineBuffer.removeLast()
        }
        let line = String(decoding: lineBuffer, as: UTF8.self)
        lineBuffer.removeAll(keepingCapacity: true)

        if line.isEmpty {
            // Blank line dispatches the accumulated event.
            defer {
                dataLines.removeAll()
                eventName = nil
            }
            guard !dataLines.isEmpty else { return nil }
            return Event(event: eventName, data: dataLines.joined(separator: "\n"))
        }

        if line.hasPrefix(":") { // comment / keep-alive
            return nil
        }

        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[line.startIndex..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { // spec: strip exactly one leading space
                value = value.dropFirst()
            }
        } else {
            field = line[...]
            value = ""
        }

        switch field {
        case "data":
            dataLines.append(String(value))
        case "event":
            eventName = String(value)
        default:
            break // id, retry, unknown fields: ignored
        }
        return nil
    }
}
