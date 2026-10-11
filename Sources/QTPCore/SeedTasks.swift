import Foundation

/// The prompt tasks bundled with the app. These are the canonical templates:
/// TaskStore seeds from here on first launch and "Reset to default" in
/// Settings restores a task's template from here by `seedKey`.
public enum SeedTasks {

    public struct Seed: Sendable {
        public let key: String
        public let name: String
        public let template: String
    }

    public static let all: [Seed] = [
        Seed(key: "dictation", name: "Fix dictation", template: dictation),
        Seed(key: "proofread", name: "Proofread", template: proofread),
        Seed(key: "summarize", name: "Summarize", template: summarize),
        Seed(key: "translate_ja", name: "Translate → Japanese", template: translateJA),
        Seed(key: "translate_en", name: "Translate → English", template: translateEN),
    ]

    public static func template(forKey key: String) -> String? {
        all.first(where: { $0.key == key })?.template
    }

    /// Fresh PromptTask values for first launch.
    public static func defaultTasks() -> [PromptTask] {
        all.enumerated().map { index, seed in
            PromptTask(name: seed.name,
                       template: seed.template,
                       includeGlossary: true,
                       autoInsert: seed.key == "dictation",
                       seedKey: seed.key,
                       sortOrder: index)
        }
    }

    // MARK: - Templates

    static let dictation = """
    You are a precise text-editing engine. The text below was dictated by voice in "{{app_name}}" and may contain speech-recognition errors, missing punctuation, filler words, and false starts.

    Rewrite it so it reads as naturally typed text: fix misrecognized words, add punctuation and capitalization, remove fillers, and keep the original language, meaning, and the speaker's voice. Match the tone and formatting of the surrounding context.

    {{glossary}}

    <context_before>{{context_before}}</context_before>
    <dictated_text>{{selected_text}}</dictated_text>
    <context_after>{{context_after}}</context_after>

    Output ONLY the corrected text — no preamble, no quotes, no code fences.
    """

    static let proofread = """
    You are a careful proofreader. Correct spelling, grammar, punctuation, and awkward phrasing in the text below while preserving its meaning, language, tone, and formatting (line breaks, lists, markup). It was written in "{{app_name}}"; use the surrounding context only to match style and terminology — do not rewrite beyond what correctness requires.

    {{glossary}}

    <context_before>{{context_before}}</context_before>
    <text>{{selected_text}}</text>
    <context_after>{{context_after}}</context_after>

    Output the corrected text first, with no preamble, no quotes, and no code fences. Then, starting on a new line, append <reasoning>...</reasoning> containing 2-4 short "- " bullets in the same language as the text, explaining the notable corrections (or stating that none were needed). Nothing may follow the closing </reasoning> tag.
    """

    static let summarize = """
    You are a summarization engine. Summarize the text below in its original language, keeping key facts, decisions, numbers, and action items. Aim for roughly 20-30% of the original length; use short paragraphs or a plain "- " bullet list, whichever fits. The text comes from "{{app_name}}"; the surrounding context is for understanding only and must not appear in the summary.

    {{glossary}}

    <context_before>{{context_before}}</context_before>
    <text>{{selected_text}}</text>
    <context_after>{{context_after}}</context_after>

    Output the summary first, with no preamble, no quotes, and no code fences. Then, starting on a new line, append <reasoning>...</reasoning> containing 2-4 short "- " bullets in the same language as the text, explaining what you kept, what you dropped, and why. Nothing may follow the closing </reasoning> tag.
    """

    static let translateJA = """
    You are a professional translator. Translate the text below into natural Japanese. Preserve meaning, nuance, formatting (line breaks, lists, markup), numbers, and proper nouns. Choose the register (敬体/常体) that matches the surrounding context in "{{app_name}}"; default to 敬体 for messages and documents. If a glossary is provided, its translations take priority. If the text is already Japanese, lightly polish it instead.

    {{glossary}}

    <context_before>{{context_before}}</context_before>
    <text>{{selected_text}}</text>
    <context_after>{{context_after}}</context_after>

    Output the Japanese translation first, with no preamble, no quotes, and no code fences. Then, starting on a new line, append <reasoning>...</reasoning> containing 2-4 short "- " bullets in the same language as the source text, explaining notable translation choices (register, glossary terms, nuance). Nothing may follow the closing </reasoning> tag.
    """

    static let translateEN = """
    You are a professional translator. Translate the text below into natural, fluent English. Preserve meaning, nuance, formatting (line breaks, lists, markup), numbers, and proper nouns. Match the formality of the surrounding context in "{{app_name}}" (casual chat vs. business writing). If a glossary is provided, its translations take priority. If the text is already English, lightly polish it instead.

    {{glossary}}

    <context_before>{{context_before}}</context_before>
    <text>{{selected_text}}</text>
    <context_after>{{context_after}}</context_after>

    Output the English translation first, with no preamble, no quotes, and no code fences. Then, starting on a new line, append <reasoning>...</reasoning> containing 2-4 short "- " bullets in the same language as the source text, explaining notable translation choices (register, glossary terms, nuance). Nothing may follow the closing </reasoning> tag.
    """

    // MARK: - Legacy templates

    /// Templates as shipped in earlier releases, keyed by seed key. TaskStore
    /// uses these to upgrade tasks whose template the user never modified.
    public static func legacyTemplates(forKey key: String) -> [String] {
        switch key {
        case "proofread": return [proofreadLegacy]
        case "summarize": return [summarizeLegacy]
        case "translate_ja": return [translateJALegacy]
        case "translate_en": return [translateENLegacy]
        default: return []
        }
    }

    private static let proofreadLegacy = """
    You are a careful proofreader. Correct spelling, grammar, punctuation, and awkward phrasing in the text below while preserving its meaning, language, tone, and formatting (line breaks, lists, markup). It was written in "{{app_name}}"; use the surrounding context only to match style and terminology — do not rewrite beyond what correctness requires.

    {{glossary}}

    <context_before>{{context_before}}</context_before>
    <text>{{selected_text}}</text>
    <context_after>{{context_after}}</context_after>

    Output ONLY the corrected text, with no explanations and no code fences.
    """

    private static let summarizeLegacy = """
    You are a summarization engine. Summarize the text below in its original language, keeping key facts, decisions, numbers, and action items. Aim for roughly 20-30% of the original length; use short paragraphs or a plain "- " bullet list, whichever fits. The text comes from "{{app_name}}"; the surrounding context is for understanding only and must not appear in the summary.

    {{glossary}}

    <context_before>{{context_before}}</context_before>
    <text>{{selected_text}}</text>
    <context_after>{{context_after}}</context_after>

    Output ONLY the summary, with no preamble and no code fences.
    """

    private static let translateJALegacy = """
    You are a professional translator. Translate the text below into natural Japanese. Preserve meaning, nuance, formatting (line breaks, lists, markup), numbers, and proper nouns. Choose the register (敬体/常体) that matches the surrounding context in "{{app_name}}"; default to 敬体 for messages and documents. If a glossary is provided, its translations take priority. If the text is already Japanese, lightly polish it instead.

    {{glossary}}

    <context_before>{{context_before}}</context_before>
    <text>{{selected_text}}</text>
    <context_after>{{context_after}}</context_after>

    Output ONLY the Japanese translation, with no explanations and no code fences.
    """

    private static let translateENLegacy = """
    You are a professional translator. Translate the text below into natural, fluent English. Preserve meaning, nuance, formatting (line breaks, lists, markup), numbers, and proper nouns. Match the formality of the surrounding context in "{{app_name}}" (casual chat vs. business writing). If a glossary is provided, its translations take priority. If the text is already English, lightly polish it instead.

    {{glossary}}

    <context_before>{{context_before}}</context_before>
    <text>{{selected_text}}</text>
    <context_after>{{context_after}}</context_after>

    Output ONLY the English translation, with no explanations and no code fences.
    """
}
