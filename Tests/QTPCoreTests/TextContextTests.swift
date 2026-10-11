import XCTest
@testable import QTPCore

final class TextContextTests: XCTestCase {

    func testASCIISlice() {
        XCTAssertEqual(TextContext.utf16Slice("hello", location: 1, length: 3), "ell")
    }

    func testClamping() {
        XCTAssertEqual(TextContext.utf16Slice("abc", location: -5, length: 100), "abc")
        XCTAssertEqual(TextContext.utf16Slice("abc", location: 10, length: 5), "")
        XCTAssertEqual(TextContext.utf16Slice("abc", location: 1, length: 0), "")
        XCTAssertEqual(TextContext.utf16Slice("", location: 0, length: 5), "")
    }

    func testSurrogatePairCutDropsBrokenHalf() {
        // "a😀b" in UTF-16: [a][D83D][DE00][b]
        let s = "a😀b"
        XCTAssertEqual(Array(s.utf16).count, 4)
        // Cut after the high surrogate → the broken half is dropped.
        XCTAssertEqual(TextContext.utf16Slice(s, location: 0, length: 2), "a")
        // Start on the low surrogate → the broken half is dropped.
        XCTAssertEqual(TextContext.utf16Slice(s, location: 2, length: 2), "b")
        // Whole pair survives.
        XCTAssertEqual(TextContext.utf16Slice(s, location: 1, length: 2), "😀")
    }

    func testContextWindows() {
        // "0123456789", selection = "45"
        let (before, after) = TextContext.contextWindows(fullText: "0123456789",
                                                         selectionLocation: 4,
                                                         selectionLength: 2,
                                                         radius: 3)
        XCTAssertEqual(before, "123")
        XCTAssertEqual(after, "678")
    }

    func testContextWindowsNearDocumentStart() {
        // Selection begins within `radius` units of the start: the before
        // window must clamp to the document start, not come back short.
        let (before1, after1) = TextContext.contextWindows(fullText: "0123456789",
                                                           selectionLocation: 3,
                                                           selectionLength: 2,
                                                           radius: 10)
        XCTAssertEqual(before1, "012")
        XCTAssertEqual(after1, "56789")

        let (before2, _) = TextContext.contextWindows(fullText: "0123456789",
                                                      selectionLocation: 2,
                                                      selectionLength: 1,
                                                      radius: 3)
        XCTAssertEqual(before2, "01")
    }

    func testContextWindowsAtEdges() {
        let (before, after) = TextContext.contextWindows(fullText: "abcdef",
                                                         selectionLocation: 0,
                                                         selectionLength: 6,
                                                         radius: 10)
        XCTAssertEqual(before, "")
        XCTAssertEqual(after, "")
    }

    func testBeforeRangeMath() {
        XCTAssertEqual(TextContext.beforeRange(selectionLocation: 10, radius: 4).location, 6)
        XCTAssertEqual(TextContext.beforeRange(selectionLocation: 10, radius: 4).length, 4)
        XCTAssertEqual(TextContext.beforeRange(selectionLocation: 2, radius: 400).location, 0)
        XCTAssertEqual(TextContext.beforeRange(selectionLocation: 2, radius: 400).length, 2)
        XCTAssertEqual(TextContext.beforeRange(selectionLocation: 0, radius: 400).length, 0)
    }

    func testAfterRangeMath() {
        let r1 = TextContext.afterRange(selectionLocation: 4, selectionLength: 2, radius: 3, totalLength: 10)
        XCTAssertEqual(r1.location, 6)
        XCTAssertEqual(r1.length, 3)
        let r2 = TextContext.afterRange(selectionLocation: 8, selectionLength: 2, radius: 5, totalLength: 10)
        XCTAssertEqual(r2.location, 10)
        XCTAssertEqual(r2.length, 0)
        let r3 = TextContext.afterRange(selectionLocation: 8, selectionLength: 1, radius: 5, totalLength: 10)
        XCTAssertEqual(r3.location, 9)
        XCTAssertEqual(r3.length, 1)
    }

    func testTrimReplacementEdges() {
        XCTAssertEqual(TextContext.trimReplacementEdges("\u{FFFD}ab\u{FFFD}"), "ab")
        XCTAssertEqual(TextContext.trimReplacementEdges("\u{FFFD}\u{FFFD}x"), "x")
        XCTAssertEqual(TextContext.trimReplacementEdges("a\u{FFFD}b"), "a\u{FFFD}b")
        XCTAssertEqual(TextContext.trimReplacementEdges(""), "")
    }

    func testPreview() {
        XCTAssertEqual(TextContext.preview(of: "  hello \n\n  world\t!  "), "hello world !")
        let long = String(repeating: "a", count: 100)
        let preview = TextContext.preview(of: long, maxLength: 10)
        XCTAssertEqual(preview.count, 10)
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    func testPreviewTailCollapsesWhitespace() {
        XCTAssertEqual(TextContext.previewTail(of: "  hello \n\n  world\t!  "), "hello world !")
    }

    func testPreviewTailShortTextIsUntouched() {
        XCTAssertEqual(TextContext.previewTail(of: "short", maxLength: 10), "short")
        XCTAssertEqual(TextContext.previewTail(of: ""), "")
    }

    func testPreviewTailKeepsEnd() {
        let tail = TextContext.previewTail(of: "0123456789", maxLength: 5)
        XCTAssertEqual(tail, "…6789")
        XCTAssertEqual(tail.count, 5)
    }

    func testPreviewTailWithEmoji() {
        // Character-based suffix must never split a grapheme.
        let text = "aaaa 😀😀😀"
        let tail = TextContext.previewTail(of: text, maxLength: 4)
        XCTAssertEqual(tail, "…😀😀😀")
    }
}
