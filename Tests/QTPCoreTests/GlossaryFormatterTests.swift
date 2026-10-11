import XCTest
@testable import QTPCore

final class GlossaryFormatterTests: XCTestCase {

    func testEmptyGlossaryIsEmptyString() {
        XCTAssertEqual(GlossaryFormatter.format([]), "")
    }

    func testIncompleteEntriesAreSkipped() {
        let entries = [
            GlossaryEntry(term: "", preferred: "x"),
            GlossaryEntry(term: "y", preferred: "   "),
        ]
        XCTAssertEqual(GlossaryFormatter.format(entries), "")
    }

    func testSingleEntryWithNote() {
        let out = GlossaryFormatter.format([
            GlossaryEntry(term: "Bengo4", preferred: "弁護士ドットコム", note: "company name")
        ])
        XCTAssertEqual(out, """
        Preferred terminology — always use these spellings/translations:
        - "Bengo4" → "弁護士ドットコム" (company name)
        """)
    }

    func testBlankNoteOmitted() {
        let out = GlossaryFormatter.format([
            GlossaryEntry(term: "a", preferred: "b", note: "  ")
        ])
        XCTAssertTrue(out.hasSuffix("- \"a\" → \"b\""))
    }

    func testMultipleEntriesOneLineEach() {
        let out = GlossaryFormatter.format([
            GlossaryEntry(term: "a", preferred: "b"),
            GlossaryEntry(term: "c", preferred: "d"),
        ])
        XCTAssertEqual(out.components(separatedBy: "\n").count, 3)
    }
}
