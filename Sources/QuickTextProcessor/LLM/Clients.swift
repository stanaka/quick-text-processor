import Foundation
import QTPCore

// MARK: - OAuth token management

/// Owns the OAuth token set of one provider profile: Keychain persistence,
/// expiry-based refresh, and single-flight refreshing (the actor serializes
/// concurrent callers so a token is refreshed once, not once per request).
actor OAuthTokenManager {

    let profileID: UUID
    let type: ProviderType

    private var cached: OAuthTokens?

    init(profileID: UUID, type: ProviderType) {
        self.profileID = profileID
        self.type = type
    }

    func currentTokens() -> OAuthTokens? {
        if cached == nil {
            cached = Keychain.oauthTokens(profileID: profileID)
        }
        return cached
    }

    func store(_ tokens: OAuthTokens) {
        cached = tokens
        Keychain.setOAuthTokens(tokens, profileID: profileID)
    }

    func clear() {
        cached = nil
        Keychain.deleteOAuthTokens(profileID: profileID)
    }

    /// Tokens ready for a request, refreshing when within 5 min of expiry.
    func validTokens() async throws -> OAuthTokens {
        guard let tokens = currentTokens() else {
            throw LLMError.notSignedIn(signInHint)
        }
        guard tokens.needsRefresh() else { return tokens }
        return try await refresh(tokens)
    }

    /// Unconditional refresh (after a 401).
    func forceRefresh() async throws -> OAuthTokens {
        guard let tokens = currentTokens() else {
            throw LLMError.notSignedIn(signInHint)
        }
        return try await refresh(tokens)
    }

    private func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else {
            throw LLMError.notSignedIn("The saved sign-in has no refresh token — sign in again.")
        }
        let request: URLRequest
        switch type {
        case .codexOAuth:
            request = CodexWire.refreshRequest(refreshToken: refreshToken)
        case .xaiOAuth:
            request = XAIWire.refreshRequest(refreshToken: refreshToken)
        case .openAICompatible, .claudeCode:
            throw LLMError.invalidConfiguration("API-key profiles have no OAuth tokens")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LLMError.notSignedIn(
                "Token refresh failed (HTTP \(http.statusCode)) — sign in again.")
        }
        let refreshed: OAuthTokens?
        switch type {
        case .codexOAuth:
            refreshed = CodexWire.tokens(fromTokenResponse: data, existing: tokens)
        case .xaiOAuth:
            refreshed = XAIWire.tokens(fromTokenResponse: data, existing: tokens)
        case .openAICompatible, .claudeCode:
            refreshed = nil
        }
        guard let refreshed else {
            throw LLMError.notSignedIn("Token refresh returned an unexpected response — sign in again.")
        }
        store(refreshed)
        return refreshed
    }

    private var signInHint: String {
        switch type {
        case .codexOAuth:
            return "Not signed in. Open Settings → Providers and sign in with your ChatGPT account (or import the Codex CLI login)."
        case .xaiOAuth:
            return "Not signed in. Open Settings → Providers and sign in with your xAI account (or import the Grok CLI login)."
        case .openAICompatible, .claudeCode:
            return "This profile uses an API key, not OAuth."
        }
    }
}

// MARK: - Clients

struct OpenAICompatClient: LLMClient {
    let profile: ProviderProfile
    let apiKey: String

    var providerName: String { profile.name }
    var modelName: String { profile.model }

    func stream(prompt: String) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let request = try OpenAICompatWire.request(baseURL: profile.baseURL,
                                                   apiKey: apiKey,
                                                   model: profile.model,
                                                   prompt: prompt)
        return try await StreamRunner.start(request: request, kind: .chatCompletions)
    }
}

/// Shared retry shape for the two OAuth-backed clients: build → send;
/// on 401, force-refresh once and retry.
private func streamWithRefresh(manager: OAuthTokenManager,
                               makeRequest: @Sendable (OAuthTokens) throws -> URLRequest)
    async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
    var tokens = try await manager.validTokens()
    do {
        return try await StreamRunner.start(request: try makeRequest(tokens), kind: .responses)
    } catch LLMError.http(let status, _) where status == 401 {
        tokens = try await manager.forceRefresh()
        return try await StreamRunner.start(request: try makeRequest(tokens), kind: .responses)
    }
}

final class CodexClient: LLMClient {
    let profile: ProviderProfile
    let manager: OAuthTokenManager

    init(profile: ProviderProfile, manager: OAuthTokenManager) {
        self.profile = profile
        self.manager = manager
    }

    var providerName: String { profile.name }
    var modelName: String { profile.model }

    func stream(prompt: String) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let profile = self.profile
        return try await streamWithRefresh(manager: manager) { tokens in
            try CodexWire.chatRequest(tokens: tokens,
                                      model: profile.model,
                                      prompt: prompt,
                                      instructions: CodexInstructions.text)
        }
    }
}

final class XAIClient: LLMClient {
    let profile: ProviderProfile
    let manager: OAuthTokenManager

    init(profile: ProviderProfile, manager: OAuthTokenManager) {
        self.profile = profile
        self.manager = manager
    }

    var providerName: String { profile.name }
    var modelName: String { profile.model }

    func stream(prompt: String) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let profile = self.profile
        let version = AppVersion.short
        return try await streamWithRefresh(manager: manager) { tokens in
            try XAIWire.chatRequest(tokens: tokens,
                                    model: profile.model,
                                    prompt: prompt,
                                    clientVersion: version)
        }
    }
}

enum AppVersion {
    static let short: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
}

struct ClaudeCodeClient: LLMClient {
    let profile: ProviderProfile
    var providerName: String { profile.name }
    var modelName: String { profile.model }

    func stream(prompt: String) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        try Task.checkCancellation()
        return try ClaudeCodeRunner.start(prompt: prompt, model: profile.model,
                                          executablePath: profile.executablePath)
    }
}
