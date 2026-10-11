import XCTest
@testable import QTPCore

final class SSEParserTests: XCTestCase {

    private func feedString(_ parser: inout SSEParser, _ s: String) -> [SSEParser.Event] {
        parser.feed(Array(s.utf8))
    }

    func testSimpleEvent() {
        var parser = SSEParser()
        let events = feedString(&parser, "data: hello\n\n")
        XCTAssertEqual(events, [SSEParser.Event(data: "hello")])
    }

    func testEventSplitAcrossChunks() {
        var parser = SSEParser()
        XCTAssertEqual(feedString(&parser, "data: hel"), [])
        XCTAssertEqual(feedString(&parser, "lo\n"), [])
        XCTAssertEqual(feedString(&parser, "\n"), [SSEParser.Event(data: "hello")])
    }

    func testCRLF() {
        var parser = SSEParser()
        let events = feedString(&parser, "data: a\r\n\r\ndata: b\r\n\r\n")
        XCTAssertEqual(events, [SSEParser.Event(data: "a"), SSEParser.Event(data: "b")])
    }

    func testMultipleDataLinesJoined() {
        var parser = SSEParser()
        let events = feedString(&parser, "data: one\ndata: two\n\n")
        XCTAssertEqual(events, [SSEParser.Event(data: "one\ntwo")])
    }

    func testCommentsAndUnknownFieldsIgnored() {
        var parser = SSEParser()
        let events = feedString(&parser, ": keep-alive\nid: 7\nretry: 100\ndata: x\n\n")
        XCTAssertEqual(events, [SSEParser.Event(data: "x")])
    }

    func testEventNameCapturedAndReset() {
        var parser = SSEParser()
        let events = feedString(&parser, "event: response.completed\ndata: {}\n\ndata: y\n\n")
        XCTAssertEqual(events, [
            SSEParser.Event(event: "response.completed", data: "{}"),
            SSEParser.Event(event: nil, data: "y"),
        ])
    }

    func testBlankLineWithoutDataEmitsNothing() {
        var parser = SSEParser()
        XCTAssertEqual(feedString(&parser, "\n\n\n"), [])
    }

    func testValueWithoutSpaceAfterColon() {
        var parser = SSEParser()
        let events = feedString(&parser, "data:tight\n\n")
        XCTAssertEqual(events, [SSEParser.Event(data: "tight")])
    }

    func testUTF8AcrossChunkBoundary() {
        var parser = SSEParser()
        let bytes = Array("data: 日本語😀\n\n".utf8)
        // Feed byte-by-byte to force splits inside multi-byte characters.
        var events: [SSEParser.Event] = []
        for byte in bytes {
            events += parser.feed(CollectionOfOne(byte))
        }
        XCTAssertEqual(events, [SSEParser.Event(data: "日本語😀")])
    }
}
