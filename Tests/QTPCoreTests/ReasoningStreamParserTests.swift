import XCTest
@testable import QTPCore

final class ReasoningStreamParserTests: XCTestCase {

    /// Feeds `chunks` and finishes; returns the concatenated answer and reasoning.
    private func run(_ chunks: [String]) -> (answer: String, reasoning: String) {
        var parser = ReasoningStreamParser()
        var answer = ""
        var reasoning = ""
        for chunk in chunks {
            let update = parser.feed(chunk)
            answer += update.answerDelta
            reasoning += update.reasoningDelta
        }
        let final = parser.finish()
        answer += final.answerDelta
        reasoning += final.reasoningDelta
        return (answer, reasoning)
    }

    func testAnswerOnlyPassesThrough() {
        let result = run(["Hello, ", "world."])
        XCTAssertEqual(result.answer, "Hello, world.")
        XCTAssertEqual(result.reasoning, "")
    }

    func testFullBlockInOneChunk() {
        let result = run(["Fixed text.\n<reasoning>- typo fixed</reasoning>"])
        XCTAssertEqual(result.answer, "Fixed text.")
        XCTAssertEqual(result.reasoning, "- typo fixed")
    }

    func testCharacterByCharacterStream() {
        let input = "Fixed text.\n<reasoning>- typo fixed\n- casing</reasoning>"
        let result = run(input.map(String.init))
        XCTAssertEqual(result.answer, "Fixed text.")
        XCTAssertEqual(result.reasoning, "- typo fixed\n- casing")
    }

    func testOpenTagSplitAcrossChunksWithoutCloseTag() {
        let result = run(["Fixed text.\n<reas", "oning>because it was wrong"])
        XCTAssertEqual(result.answer, "Fixed text.")
        XCTAssertEqual(result.reasoning, "because it was wrong")
    }

    func testFalseAlarmPrefixIsReleasedAsAnswer() {
        let result = run(["a <reas", "onable idea"])
        XCTAssertEqual(result.answer, "a <reasonable idea")
        XCTAssertEqual(result.reasoning, "")
    }

    func testWhitespaceBeforeTagIsStrippedFromAnswer() {
        let result = run(["answer", " \n\n", "<reasoning>why</reasoning>"])
        XCTAssertEqual(result.answer, "answer")
        XCTAssertEqual(result.reasoning, "why")
    }

    func testTextAfterCloseTagStaysInReasoning() {
        let result = run(["answer\n<reasoning>why</reasoning>stray text"])
        XCTAssertEqual(result.answer, "answer")
        XCTAssertEqual(result.reasoning, "whystray text")
    }

    func testFinishFlushesPartialTagAsAnswer() {
        // A truncated tag at end of stream is the model's own text; keep it.
        let result = run(["answer <reas"])
        XCTAssertEqual(result.answer, "answer <reas")
        XCTAssertEqual(result.reasoning, "")
    }

    func testTrailingWhitespaceInReasoningIsTrimmedAtFinish() {
        let result = run(["answer\n<reasoning>why\n\n"])
        XCTAssertEqual(result.answer, "answer")
        XCTAssertEqual(result.reasoning, "why")
    }

    func testAnswerStreamsBeforeTagArrives() {
        // The answer must be emitted incrementally, not held until finish.
        var parser = ReasoningStreamParser()
        let first = parser.feed("The corrected sentence. ")
        XCTAssertEqual(first.answerDelta, "The corrected sentence.")
        let second = parser.feed("More text")
        XCTAssertEqual(second.answerDelta, " More text")
    }

    func testMultilineReasoningStreamsIncrementally() {
        var parser = ReasoningStreamParser()
        let first = parser.feed("answer\n<reasoning>- one\n")
        XCTAssertEqual(first.reasoningDelta, "- one")
        // The held-back newline (a possible tag boundary) is released with the
        // next chunk once it can no longer start the close tag.
        let second = parser.feed("- two")
        XCTAssertEqual(second.reasoningDelta, "\n- two")
        let final = parser.finish()
        XCTAssertEqual(final.reasoningDelta, "")
    }
}
