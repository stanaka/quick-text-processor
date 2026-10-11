import Foundation

/// Constants and request building for the ChatGPT-account ("codex-oauth")
/// provider. All values verified against the open-source Codex CLI
/// (github.com/openai/codex, codex-rs/login) and the opencode codex-auth
/// plugin. If OpenAI changes the contract, this file is the only place to fix.
public enum CodexWire {

    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let issuer = "https://auth.openai.com"
    public static let authorizeEndpoint = "https://auth.openai.com/oauth/authorize"
    public static let tokenEndpoint = "https://auth.openai.com/oauth/token"
    /// The redirect port is registered with the OAuth client and cannot vary.
    public static let redirectPort: UInt16 = 1455
    public static let redirectPath = "/auth/callback"
    public static let redirectURI = "http://localhost:1455/auth/callback"
    public static let scope = "openid profile email offline_access"
    public static let chatEndpoint = "https://chatgpt.com/backend-api/codex/responses"
    public static let modelsEndpoint = "https://chatgpt.com/backend-api/codex/models"
    public static let originator = "codex_cli_rs"
    /// The JWT claim namespace carrying the ChatGPT account id.
    public static let authClaimNamespace = "https://api.openai.com/auth"

    /// Fallback candidates shown before the live catalog has been fetched,
    /// from the Codex CLI's bundled model catalog (picker-visible entries,
    /// by priority). The settings UI always allows free-text entry too.
    public static let fallbackModelCandidates = [
        "gpt-5.6-sol",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
        "gpt-5.5",
        "gpt-5.2",
    ]

    // MARK: - OAuth flow

    public static func authorizeURL(challenge: String, state: String) -> URL? {
        var components = URLComponents(string: authorizeEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: originator),
        ]
        return components?.url
    }

    public static func tokenExchangeRequest(code: String, verifier: String) -> URLRequest {
        formPOST(url: tokenEndpoint, fields: [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", verifier),
        ])
    }

    public static func refreshRequest(refreshToken: String) -> URLRequest {
        formPOST(url: tokenEndpoint, fields: [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientID),
            ("scope", "openid profile email"),
        ])
    }

    /// Parses an /oauth/token response (exchange or refresh) into OAuthTokens.
    /// `existing` fills gaps a refresh response omits (id_token, account id).
    public static func tokens(fromTokenResponse data: Data,
                              existing: OAuthTokens? = nil) -> OAuthTokens? {
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data),
              let accessToken = response.access_token else {
            return nil
        }
        let idToken = response.id_token ?? existing?.idToken
        var expiresAt: Date?
        if let expiresIn = response.expires_in {
            expiresAt = Date().addingTimeInterval(expiresIn)
        } else {
            expiresAt = JWT.expiration(accessToken)
        }
        let accountID = idToken.flatMap { Self.accountID(fromIDToken: $0) }
            ?? existing?.accountID
        return OAuthTokens(accessToken: accessToken,
                           refreshToken: response.refresh_token ?? existing?.refreshToken,
                           idToken: idToken,
                           accountID: accountID,
                           expiresAt: expiresAt)
    }

    public static func accountID(fromIDToken idToken: String) -> String? {
        JWT.stringClaim(idToken, path: [authClaimNamespace, "chatgpt_account_id"])
    }

    // MARK: - Chat request

    public static func chatRequest(tokens: OAuthTokens,
                                   model: String,
                                   prompt: String,
                                   instructions: String) throws -> URLRequest {
        guard let accountID = tokens.accountID else {
            throw LLMError.notSignedIn("The ChatGPT account id is missing — sign in again.")
        }
        guard let url = URL(string: chatEndpoint) else {
            throw LLMError.invalidConfiguration("Invalid codex endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue(originator, forHTTPHeaderField: "originator")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "session_id")
        // store:false + stream:true are required by the backend; the include
        // mirrors what codex itself sends for reasoning-capable models.
        request.httpBody = try ResponsesWire.bodyData(model: model,
                                                      instructions: instructions,
                                                      prompt: prompt,
                                                      include: ["reasoning.encrypted_content"])
        request.timeoutInterval = 300
        return request
    }

    // MARK: - Models listing

    /// GET /backend-api/codex/models — the catalog the Codex CLI's model
    /// picker is built from.
    public static func modelsRequest(tokens: OAuthTokens,
                                     clientVersion: String) throws -> URLRequest {
        guard let accountID = tokens.accountID else {
            throw LLMError.notSignedIn("The ChatGPT account id is missing — sign in again.")
        }
        guard let url = URL(string: modelsEndpoint + "?client_version=\(clientVersion)") else {
            throw LLMError.invalidConfiguration("Invalid codex models endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue(originator, forHTTPHeaderField: "originator")
        request.timeoutInterval = 30
        return request
    }

    /// Decodes a models response ({"models":[{"slug","visibility","priority"}]})
    /// into picker-visible slugs, sorted by catalog priority. Unknown shapes
    /// yield [].
    public static func modelIDs(fromModelsResponse data: Data) -> [String] {
        guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return []
        }
        return (response.models ?? [])
            .filter { $0.visibility == "list" }
            .sorted { ($0.priority ?? .max) < ($1.priority ?? .max) }
            .compactMap(\.slug)
            .filter { !$0.isEmpty }
    }

    // MARK: - Codex CLI credential import (~/.codex/auth.json, read-only)

    public static var cliAuthFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    /// Parses the Codex CLI's auth.json contents. Never writes that file.
    public static func importCLITokens(json data: Data) -> OAuthTokens? {
        guard let file = try? JSONDecoder().decode(CLIAuthFile.self, from: data),
              let tokens = file.tokens,
              let accessToken = tokens.access_token else {
            return nil
        }
        let accountID = tokens.account_id
            ?? tokens.id_token.flatMap { self.accountID(fromIDToken: $0) }
        return OAuthTokens(accessToken: accessToken,
                           refreshToken: tokens.refresh_token,
                           idToken: tokens.id_token,
                           accountID: accountID,
                           expiresAt: JWT.expiration(accessToken))
    }

    // MARK: - Wire structs

    private struct ModelsResponse: Decodable {
        struct Model: Decodable {
            let slug: String?
            let visibility: String?
            let priority: Int?
        }
        let models: [Model]?
    }

    private struct TokenResponse: Decodable {
        let id_token: String?
        let access_token: String?
        let refresh_token: String?
        let expires_in: TimeInterval?
    }

    private struct CLIAuthFile: Decodable {
        struct Tokens: Decodable {
            let id_token: String?
            let access_token: String?
            let refresh_token: String?
            let account_id: String?
        }
        let tokens: Tokens?
    }

    static func formPOST(url: String, fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormBody.encode(fields)
        request.timeoutInterval = 60
        return request
    }
}
