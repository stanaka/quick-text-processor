import Foundation

/// Splits a streamed LLM response into the answer text and an optional
/// trailing <reasoning>…</reasoning> block, tolerating tags that straddle
/// delta chunk boundaries. Prompts that never emit the block degrade to
/// answer-only output, so the parser is safe for user-customized templates.
public struct ReasoningStreamParser {

    public struct Update: Equatable, Sendable {
        public var answerDelta: String
        public var reasoningDelta: String

        public init(answerDelta: String = "", reasoningDelta: String = "") {
            self.answerDelta = answerDelta
            self.reasoningDelta = reasoningDelta
        }

        public var isEmpty: Bool { answerDelta.isEmpty && reasoningDelta.isEmpty }
    }

    private enum Section {
        case answer
        case reasoning
    }

    private static let openTag = "<reasoning>"
    private static let closeTag = "</reasoning>"

    private var section: Section = .answer
    /// Text held back because it may be (whitespace followed by) the start of
    /// the tag we are looking for, split across chunks.
    private var pending = ""

    public init() {}

    /// Feed one streamed delta; returns the text that can be safely emitted.
    public mutating func feed(_ delta: String) -> Update {
        pending += delta
        var update = Update()
        while true {
            switch section {
            case .answer:
                if let range = pending.range(of: Self.openTag) {
                    // The answer ends here; drop the tag and the whitespace
                    // separating it from the answer.
                    let answer = String(pending[..<range.lowerBound])
                    update.answerDelta += trimTrailingWhitespace(answer)
                    pending = String(pending[range.upperBound...])
                    section = .reasoning
                    continue
                }
                update.answerDelta += releaseAllButHoldback(for: Self.openTag)
            case .reasoning:
                if let range = pending.range(of: Self.closeTag) {
                    // Defensive: stray text after the close tag stays in the
                    // reasoning so it can never contaminate the insertable answer.
                    update.reasoningDelta += String(pending[..<range.lowerBound])
                    pending = String(pending[range.upperBound...])
                    continue
                }
                update.reasoningDelta += releaseAllButHoldback(for: Self.closeTag)
            }
            return update
        }
    }

    /// Flush at end of stream: a partial tag that never completed is the
    /// model's own text, so it is released rather than dropped.
    public mutating func finish() -> Update {
        defer { pending = "" }
        switch section {
        case .answer:
            return Update(answerDelta: pending)
        case .reasoning:
            return Update(reasoningDelta: trimTrailingWhitespace(pending))
        }
    }

    /// Removes and returns everything in `pending` except the longest suffix
    /// that could still grow into (whitespace +) `tag` on a later chunk.
    private mutating func releaseAllButHoldback(for tag: String) -> String {
        var index = pending.startIndex
        while index < pending.endIndex {
            let suffix = pending[index...]
            let trimmed = suffix.drop(while: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
            if trimmed.count < tag.count && tag.hasPrefix(trimmed) {
                break
            }
            index = pending.index(after: index)
        }
        let released = String(pending[..<index])
        pending = String(pending[index...])
        return released
    }

    private func trimTrailingWhitespace(_ text: String) -> String {
        var scalars = text.unicodeScalars
        while let last = scalars.last, CharacterSet.whitespacesAndNewlines.contains(last) {
            scalars.removeLast()
        }
        return String(scalars)
    }
}
