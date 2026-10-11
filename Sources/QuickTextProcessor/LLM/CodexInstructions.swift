import Foundation

/// The `instructions` field sent to the ChatGPT codex backend.
///
/// The backend only accepts requests whose instructions match the official
/// Codex prompts, so the app bundles a snapshot of
/// openai/codex@main:codex-rs/core/gpt-5.2-codex_prompt.md
/// (Resources/codex_instructions.md) and sends the actual task prompt as a
/// regular user input item. If OpenAI rotates the accepted prompt, replace the
/// resource file with the current one from that repository.
enum CodexInstructions {

    static let text: String = {
        if let url = Bundle.module.url(forResource: "codex_instructions", withExtension: "md"),
           let contents = try? String(contentsOf: url, encoding: .utf8),
           !contents.isEmpty {
            return contents
        }
        return fallback
    }()

    /// Minimal fallback if the resource is missing from the bundle.
    private static let fallback =
        "You are Codex, based on GPT-5. You are running as a coding agent in the Codex CLI on a user's computer."
}
