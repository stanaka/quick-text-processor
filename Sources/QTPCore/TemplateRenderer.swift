import Foundation

/// Fills `{{placeholder}}` slots in a prompt template.
///
/// Substitution is SINGLE-PASS: replaced values are never rescanned, so text
/// that itself contains `{{...}}` (e.g. inside the user's selection) can never
/// inject further expansion. Unknown placeholders are left verbatim so typos
/// in a custom template are visible instead of silently vanishing.
public enum TemplateRenderer {

    public static func render(_ template: String, values: [String: String]) -> String {
        var out = ""
        out.reserveCapacity(template.count)
        var cursor = template.startIndex

        while cursor < template.endIndex,
              let open = template.range(of: "{{", range: cursor..<template.endIndex) {
            out += template[cursor..<open.lowerBound]
            guard let close = template.range(of: "}}", range: open.upperBound..<template.endIndex) else {
                // Unterminated "{{" — emit the rest verbatim.
                cursor = open.lowerBound
                break
            }
            let rawKey = String(template[open.upperBound..<close.lowerBound])
            let key = rawKey.trimmingCharacters(in: .whitespaces)
            if let value = values[key] {
                out += value
            } else {
                out += template[open.lowerBound..<close.upperBound]
            }
            cursor = close.upperBound
        }

        out += template[cursor...]
        return out
    }
}
