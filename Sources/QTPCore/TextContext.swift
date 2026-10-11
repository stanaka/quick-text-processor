import Foundation

/// UTF-16 range math for Accessibility text.
///
/// AX selection ranges (kAXSelectedTextRangeAttribute) are CFRanges counted in
/// UTF-16 code units — NSString semantics, NOT Swift Characters. Slicing with
/// Swift's Character-based prefix/suffix on those counts corrupts positions,
/// and cutting inside a surrogate pair (emoji, 𠮷, ...) produces invalid
/// strings. Everything here clamps and repairs edges instead of trusting them.
public enum TextContext {

    /// Slice `value` by a UTF-16 (location, length) range. The range is clamped
    /// to the string; a cut through a surrogate pair drops the broken half.
    public static func utf16Slice(_ value: String, location: Int, length: Int) -> String {
        let utf16 = Array(value.utf16)
        let total = utf16.count
        let start = min(max(0, location), total)
        let end = min(max(start, location + max(0, length)), total)
        guard start < end else { return "" }
        return string(fromUTF16: Array(utf16[start..<end]))
    }

    /// Context windows of up to `radius` UTF-16 units on each side of the
    /// selection inside `fullText`.
    public static func contextWindows(fullText: String,
                                      selectionLocation: Int,
                                      selectionLength: Int,
                                      radius: Int) -> (before: String, after: String) {
        let loc = max(0, selectionLocation)
        let len = max(0, selectionLength)
        // Pass the full radius and let the slice clamp the (possibly negative)
        // start — computing the length here would shorten the window whenever
        // the selection sits within `radius` units of the document start.
        let before = utf16Slice(fullText, location: loc - radius, length: radius)
        let after = utf16Slice(fullText, location: loc + len, length: radius)
        return (before, after)
    }

    /// Clamped (location, length) for the window BEFORE a selection, in UTF-16
    /// units — for parameterized AX fetches (AXStringForRange).
    public static func beforeRange(selectionLocation: Int, radius: Int) -> (location: Int, length: Int) {
        let loc = max(0, selectionLocation)
        let start = max(0, loc - radius)
        return (start, loc - start)
    }

    /// Clamped (location, length) for the window AFTER a selection.
    /// `totalLength` is kAXNumberOfCharactersAttribute; pass Int.max if unknown.
    public static func afterRange(selectionLocation: Int,
                                  selectionLength: Int,
                                  radius: Int,
                                  totalLength: Int) -> (location: Int, length: Int) {
        let start = max(0, selectionLocation) + max(0, selectionLength)
        guard start < totalLength else { return (max(0, min(start, totalLength)), 0) }
        return (start, min(radius, totalLength - start))
    }

    /// Builds a String from UTF-16 units, dropping a broken surrogate half at
    /// either edge (a leading low surrogate or a trailing high surrogate).
    static func string(fromUTF16 units: [UInt16]) -> String {
        var units = units
        if let first = units.first, (0xDC00...0xDFFF).contains(first) {
            units.removeFirst()
        }
        if let last = units.last, (0xD800...0xDBFF).contains(last) {
            units.removeLast()
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// AX can hand back strings whose edges were cut through a surrogate pair;
    /// bridging turns the halves into U+FFFD. Trim those replacement characters
    /// from the edges (interior ones are left alone — they may be real).
    public static func trimReplacementEdges(_ s: String) -> String {
        var result = Substring(s)
        while result.first == "\u{FFFD}" { result.removeFirst() }
        while result.last == "\u{FFFD}" { result.removeLast() }
        return String(result)
    }

    /// Single-line preview for UI (palette / history rows): whitespace runs
    /// collapse to single spaces, truncated to `maxLength` Characters.
    public static func preview(of text: String, maxLength: Int = 80) -> String {
        let collapsed = collapseWhitespace(text)
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(max(0, maxLength - 1))) + "…"
    }

    /// Like `preview`, but keeps the END of the text and truncates from the
    /// head with a leading "…" — for context-before, where the characters
    /// adjacent to the selection are the interesting ones.
    public static func previewTail(of text: String, maxLength: Int = 80) -> String {
        let collapsed = collapseWhitespace(text)
        guard collapsed.count > maxLength else { return collapsed }
        return "…" + String(collapsed.suffix(max(0, maxLength - 1)))
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
