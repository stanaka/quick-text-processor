import XCTest
@testable import QTPCore

final class WireDecodingTests: XCTestCase {

    // MARK: - chat/completions

    func testChatDoneSentinel() {
        XCTAssertEqual(OpenAICompatWire.decode(data: "[DONE]"), [.done])
    }

    func testChatDelta() {
        let json = #"{"choices":[{"delta":{"content":"Hi"}}]}"#
        XCTAssertEqual(OpenAICompatWire.decode(data: json), [.delta("Hi")])
    }

    func testChatFinishReasonEndsStream() {
        let json = #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        XCTAssertEqual(OpenAICompatWire.decode(data: json), [.done])
    }

    func testChatDeltaAndFinishTogether() {
        let json = #"{"choices":[{"delta":{"content":"end"},"finish_reason":"stop"}]}"#
        XCTAssertEqual(OpenAICompatWire.decode(data: json), [.delta("end"), .done])
    }

    func testChatInStreamError() {
        let json = #"{"error":{"message":"boom"}}"#
        XCTAssertEqual(OpenAICompatWire.decode(data: json), [.failed("boom")])
    }

    func testChatGarbageIgnored() {
        XCTAssertEqual(OpenAICompatWire.decode(data: "not json"), [])
    }

    func testErrorMessageParsing() {
        let body = Data(#"{"error":{"message":"Invalid API key"}}"#.utf8)
        XCTAssertEqual(OpenAICompatWire.errorMessage(status: 401, body: body), "Invalid API key")

        let plain = Data("service melted".utf8)
        XCTAssertEqual(OpenAICompatWire.errorMessage(status: 500, body: plain), "service melted")
    }

    // MARK: - Responses (codex & xai)

    func testResponsesOutputTextDelta() {
        let json = #"{"type":"response.output_text.delta","delta":"He"}"#
        XCTAssertEqual(ResponsesWire.decode(eventName: nil, data: json), [.delta("He")])
    }

    func testResponsesCompleted() {
        let json = #"{"type":"response.completed","response":{}}"#
        XCTAssertEqual(ResponsesWire.decode(eventName: nil, data: json), [.done])
    }

    func testResponsesFailedSurfacesMessage() {
        let json = #"{"type":"response.failed","response":{"error":{"message":"quota exceeded"}}}"#
        XCTAssertEqual(ResponsesWire.decode(eventName: nil, data: json), [.failed("quota exceeded")])
    }

    func testResponsesTopLevelError() {
        let json = #"{"type":"error","message":"bad request"}"#
        XCTAssertEqual(ResponsesWire.decode(eventName: nil, data: json), [.failed("bad request")])
    }

    func testResponsesUnknownEventsIgnored() {
        for type in ["response.created", "response.in_progress",
                     "response.output_item.added", "response.reasoning_summary_text.delta"] {
            let json = #"{"type":"\#(type)"}"#
            XCTAssertEqual(ResponsesWire.decode(eventName: nil, data: json), [], "type=\(type)")
        }
    }

    func testResponsesFallsBackToSSEEventName() {
        let events = ResponsesWire.decode(eventName: "response.completed", data: "{}")
        XCTAssertEqual(events, [.done])
    }
}
