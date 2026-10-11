import XCTest
@testable import QTPCore

final class LoopbackParseTests: XCTestCase {

    func testParsesCodeAndState() throws {
        let head = "GET /auth/callback?code=abc123&state=st9 HTTP/1.1\r\nHost: localhost:1455\r\n\r\n"
        let callback = try XCTUnwrap(LoopbackRequestParser.parse(requestHead: head))
        XCTAssertEqual(callback.path, "/auth/callback")
        XCTAssertEqual(callback.query["code"], "abc123")
        XCTAssertEqual(callback.query["state"], "st9")
    }

    func testPercentDecoding() throws {
        let head = "GET /callback?code=a%2Bb%20c HTTP/1.1\r\n"
        let callback = try XCTUnwrap(LoopbackRequestParser.parse(requestHead: head))
        XCTAssertEqual(callback.query["code"], "a+b c")
    }

    func testFaviconParsesToOtherPath() throws {
        let callback = try XCTUnwrap(LoopbackRequestParser.parse(requestHead: "GET /favicon.ico HTTP/1.1\r\n"))
        XCTAssertEqual(callback.path, "/favicon.ico")
        XCTAssertNil(callback.query["code"])
    }

    func testRejectsNonGETAndGarbage() {
        XCTAssertNil(LoopbackRequestParser.parse(requestHead: "POST /callback HTTP/1.1\r\n"))
        XCTAssertNil(LoopbackRequestParser.parse(requestHead: ""))
        XCTAssertNil(LoopbackRequestParser.parse(requestHead: "garbage"))
    }

    func testBareLFLineEndings() throws {
        let callback = try XCTUnwrap(LoopbackRequestParser.parse(requestHead: "GET /cb?code=x HTTP/1.1\nHost: h\n"))
        XCTAssertEqual(callback.query["code"], "x")
    }
}
