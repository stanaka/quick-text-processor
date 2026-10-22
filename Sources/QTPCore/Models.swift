import Foundation

// MARK: - Providers

public enum ProviderType: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai-compatible"
    case codexOAuth = "codex-oauth"
    case xaiOAuth = "xai-oauth"
    case claudeCode = "claude-code"

    public var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI-compatible (API key)"
        case .codexOAuth: return "Codex (ChatGPT account)"
        case .xaiOAuth: return "xAI (Grok account)"
        case .claudeCode: return "Claude Code (CLI)"
        }
    }

    /// Whether the app manages OAuth tokens for this provider.
    public var usesOAuth: Bool { self == .codexOAuth || self == .xaiOAuth }

    public var defaultModel: String {
        switch self {
        case .openAICompatible: return "gpt-4o-mini"
        case .codexOAuth: return "gpt-5.6-sol"
        case .xaiOAuth: return "grok-4.6"
        case .claudeCode: return "sonnet"
        }
    }
}

/// One configured LLM endpoint. Secrets (API key / OAuth tokens) are stored in
/// the Keychain keyed by `id`, never in this struct.
public struct ProviderProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var type: ProviderType
    /// Base URL for `openAICompatible` (e.g. "https://api.openai.com").
    /// Ignored by OAuth providers and the Claude Code CLI.
    public var baseURL: String
    public var model: String
    /// Optional absolute CLI executable path; nil means automatic discovery.
    public var executablePath: String?

    public init(id: UUID = UUID(),
                name: String,
                type: ProviderType,
                baseURL: String = "https://api.openai.com",
                model: String? = nil,
                executablePath: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.baseURL = baseURL
        self.model = model ?? type.defaultModel
        self.executablePath = executablePath
    }
}

// MARK: - Prompt tasks

/// A user-editable prompt task shown in the palette.
public struct PromptTask: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Template with {{selected_text}}, {{context_before}}, {{context_after}},
    /// {{app_name}} and {{glossary}} placeholders.
    public var template: String
    /// Append the user's glossary via {{glossary}} when non-empty.
    public var includeGlossary: Bool
    /// true: when the result is ready, the result window waits for the user's
    /// response — ⏎ inserts at the cursor, esc dismisses.
    public var autoInsert: Bool
    /// Override the default provider profile; nil = use the app-wide default.
    public var providerProfileID: UUID?
    /// Set for bundled tasks ("dictation", "proofread", ...) to enable
    /// "Reset to default" in Settings. nil for user-created tasks.
    public var seedKey: String?
    /// Palette position; index 0...8 maps to keyboard shortcuts 1...9.
    public var sortOrder: Int

    public init(id: UUID = UUID(),
                name: String,
                template: String,
                includeGlossary: Bool = true,
                autoInsert: Bool = false,
                providerProfileID: UUID? = nil,
                seedKey: String? = nil,
                sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.template = template
        self.includeGlossary = includeGlossary
        self.autoInsert = autoInsert
        self.providerProfileID = providerProfileID
        self.seedKey = seedKey
        self.sortOrder = sortOrder
    }
}

// MARK: - Glossary

/// One terminology rule injected into prompts via {{glossary}}.
public struct GlossaryEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// The term as it may appear in the text (product name, person, jargon...).
    public var term: String
    /// The preferred spelling / translation the LLM must use.
    public var preferred: String
    /// Optional hint for the LLM ("company name", "do not translate", ...).
    public var note: String

    public init(id: UUID = UUID(), term: String = "", preferred: String = "", note: String = "") {
        self.id = id
        self.term = term
        self.preferred = preferred
        self.note = note
    }
}

// MARK: - History

public struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var taskName: String
    /// Frontmost app at capture time; nil for Playground runs.
    public var appName: String?
    public var bundleID: String?
    /// The captured/selected text that was processed.
    public var input: String
    /// Surrounding text that was sent to the LLM as {{context_before}} / {{context_after}}.
    /// Empty for clipboard/Playground runs and entries recorded before this field existed.
    public var contextBefore: String
    public var contextAfter: String
    public var output: String
    /// The model's explanation of its output, when the task's prompt asked for
    /// one. Empty for prompts without a reasoning block and for older entries.
    public var reasoning: String
    public var providerName: String
    public var model: String

    public init(id: UUID = UUID(),
                date: Date = Date(),
                taskName: String,
                appName: String? = nil,
                bundleID: String? = nil,
                input: String,
                contextBefore: String = "",
                contextAfter: String = "",
                output: String,
                reasoning: String = "",
                providerName: String,
                model: String) {
        self.id = id
        self.date = date
        self.taskName = taskName
        self.appName = appName
        self.bundleID = bundleID
        self.input = input
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.output = output
        self.reasoning = reasoning
        self.providerName = providerName
        self.model = model
    }

    /// Hand-written so entries persisted before contextBefore/contextAfter existed
    /// still decode (JSONStore quarantines the whole file on any decode error).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        taskName = try container.decode(String.self, forKey: .taskName)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        input = try container.decode(String.self, forKey: .input)
        contextBefore = try container.decodeIfPresent(String.self, forKey: .contextBefore) ?? ""
        contextAfter = try container.decodeIfPresent(String.self, forKey: .contextAfter) ?? ""
        output = try container.decode(String.self, forKey: .output)
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        providerName = try container.decode(String.self, forKey: .providerName)
        model = try container.decode(String.self, forKey: .model)
    }
}

// MARK: - Capture

public enum CaptureSource: String, Codable, Sendable {
    case accessibility
    case clipboard
    case playground
}

/// Text captured at hotkey time. The AXUIElement that produced it lives in the
/// app target (QTPCore stays UI-free).
public struct CapturedText: Sendable {
    public var selected: String
    public var before: String
    public var after: String
    public var appName: String?
    public var bundleID: String?
    public var source: CaptureSource

    public init(selected: String,
                before: String = "",
                after: String = "",
                appName: String? = nil,
                bundleID: String? = nil,
                source: CaptureSource) {
        self.selected = selected
        self.before = before
        self.after = after
        self.appName = appName
        self.bundleID = bundleID
        self.source = source
    }

    /// Values fed into TemplateRenderer.
    public func templateValues(glossary: String) -> [String: String] {
        [
            "selected_text": selected,
            "context_before": before,
            "context_after": after,
            "app_name": appName ?? "an unknown app",
            "glossary": glossary,
        ]
    }
}

// MARK: - OAuth tokens

/// OAuth token set persisted (as JSON) in the Keychain, keyed by profile id.
public struct OAuthTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    /// Raw id_token JWT (codex); kept because the account id claim lives here.
    public var idToken: String?
    /// ChatGPT account id required by the codex backend.
    public var accountID: String?
    public var expiresAt: Date?

    public init(accessToken: String,
                refreshToken: String? = nil,
                idToken: String? = nil,
                accountID: String? = nil,
                expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.accountID = accountID
        self.expiresAt = expiresAt
    }

    /// True when the access token is missing/near expiry and should be refreshed.
    public func needsRefresh(leeway: TimeInterval = 300, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(leeway) >= expiresAt
    }
}
