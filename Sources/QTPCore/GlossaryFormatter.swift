import Foundation

/// Formats the user's glossary into the text block substituted for {{glossary}}.
public enum GlossaryFormatter {

    public static func format(_ entries: [GlossaryEntry]) -> String {
        let valid = entries.filter {
            !$0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !valid.isEmpty else { return "" }

        var lines = ["Preferred terminology — always use these spellings/translations:"]
        for entry in valid {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let preferred = entry.preferred.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = note.isEmpty ? "" : " (\(note))"
            lines.append("- \"\(term)\" → \"\(preferred)\"\(suffix)")
        }
        return lines.joined(separator: "\n")
    }
}
