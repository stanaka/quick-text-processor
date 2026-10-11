import Foundation

/// Constants and request building for the Grok-account ("xai-oauth") provider.
/// Values verified against the pi-xai-oauth extension, which mirrors the
/// official grok CLI (xai-org/grok-build). If xAI changes the contract, this
/// file (plus XAIAuthFlow in the app target) is the only place to fix.
public enum XAIWire {

    public static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    public static let issuer = "https://auth.x.ai"
    public static let authorizeEndpoint = "https://auth.x.ai/oauth2/authorize"
    public static let tokenEndpoint = "https://auth.x.ai/oauth2/token"
    public static let deviceCodeEndpoint = "https://auth.x.ai/oauth2/device/code"
    public static let scope = "openid profile email offline_access grok-cli:access api:access conversations:read conversations:write"
    /// The grok CLI's preferred loopback port; other loopback ports are accepted.
    public static let preferredPort: UInt16 = 56121
    public static let redirectPath = "/callback"
    public static let chatEndpoint = "https://cli-chat-proxy.grok.com/v1/responses"
    public static let modelsEndpoint = "https://cli-chat-proxy.grok.com/v1/models-v2"
    public static let clientIdentifier = "quick-text-processor"

    /// Fallback candidates shown before the live catalog has been fetched
    /// (only slugs the grok CLI itself defaults to). The settings UI always
    /// allows free-text entry too.
    public static let fallbackModelCandidates = [
        "grok-4.6",
        "grok-code-fast-1",
    ]

    public static func redirectURI(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/callback"
    }

    // MARK: - OAuth flow

    public static func authorizeURL(challenge: String,
                                    state: String,
                                    nonce: String,
                                    redirectURI: String) -> URL? {
        var components = URLComponents(string: authorizeEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        return components?.url
    }

    public static func tokenExchangeRequest(code: String,
                                            verifier: String,
                                            redirectURI: String) -> URLRequest {
        CodexWire.formPOST(url: tokenEndpoint, fields: [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", verifier),
        ])
    }

    public static func refreshRequest(refreshToken: String) -> URLRequest {
        CodexWire.formPOST(url: tokenEndpoint, fields: [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientID),
        ])
    }

    public static func tokens(fromTokenResponse data: Data,
                              existing: OAuthTokens? = nil) -> OAuthTokens? {
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data),
              let accessToken = response.access_token else {
            return nil
        }
        var expiresAt: Date?
        if let expiresIn = response.expires_in {
            expiresAt = Date().addingTimeInterval(expiresIn)
        } else {
            expiresAt = JWT.expiration(accessToken)
        }
        return OAuthTokens(accessToken: accessToken,
                           refreshToken: response.refresh_token ?? existing?.refreshToken,
                           idToken: response.id_token,
                           accountID: nil,
                           expiresAt: expiresAt)
    }

    // MARK: - Chat request (OAuth-backed Responses proxy)

    public static func chatRequest(tokens: OAuthTokens,
                                   model: String,
                                   prompt: String,
                                   clientVersion: String) throws -> URLRequest {
        guard let url = URL(string: chatEndpoint) else {
            throw LLMError.invalidConfiguration("Invalid xAI endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("\(clientIdentifier)/\(clientVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue(clientIdentifier, forHTTPHeaderField: "x-grok-client-identifier")
        request.setValue(clientVersion, forHTTPHeaderField: "x-grok-client-version")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("authenticate-response", forHTTPHeaderField: "x-authenticateresponse")
        request.setValue("interactive", forHTTPHeaderField: "x-grok-client-mode")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "x-grok-conv-id")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "x-grok-req-id")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "x-grok-session-id")
        request.setValue(model, forHTTPHeaderField: "x-grok-model-override")
        request.httpBody = try ResponsesWire.bodyData(model: model,
                                                      instructions: nil,
                                                      prompt: prompt)
        request.timeoutInterval = 300
        return request
    }

    // MARK: - Models listing

    /// GET /v1/models-v2 — the catalog the grok CLI's model picker is built
    /// from. Same client headers as `chatRequest`, minus the per-request ids.
    public static func modelsRequest(tokens: OAuthTokens,
                                     clientVersion: String) throws -> URLRequest {
        guard let url = URL(string: modelsEndpoint) else {
            throw LLMError.invalidConfiguration("Invalid xAI models endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("\(clientIdentifier)/\(clientVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue(clientIdentifier, forHTTPHeaderField: "x-grok-client-identifier")
        request.setValue(clientVersion, forHTTPHeaderField: "x-grok-client-version")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("interactive", forHTTPHeaderField: "x-grok-client-mode")
        request.timeoutInterval = 30
        return request
    }

    /// Decodes a models-v2 response ({"data":[{"model"|"modelId"|"id",
    /// "hidden"}]}) into visible model ids, keeping the server's curated
    /// order. Unknown shapes yield [].
    public static func modelIDs(fromModelsResponse data: Data) -> [String] {
        guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return []
        }
        var seen = Set<String>()
        var ids: [String] = []
        for entry in response.data ?? [] where entry.hidden != true {
            guard let id = entry.model ?? entry.modelId ?? entry.id,
                  !id.isEmpty, seen.insert(id).inserted else { continue }
            ids.append(id)
        }
        return ids
    }

    // MARK: - Grok CLI credential import (~/.grok/auth.json, read-only)

    public static var cliAuthFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    static var modernStorageKey: String { "\(issuer)::\(clientID)" }
    static let legacyStorageKey = "https://accounts.x.ai/sign-in"

    /// Parses the grok CLI's auth.json contents. Never writes that file.
    /// Modern entries live under "https://auth.x.ai::<clientID>" with
    /// key/access_token/token + refresh_token/refresh + expires_at
    /// (epoch seconds, epoch milliseconds, or an ISO-8601 string);
    /// legacy entries under "https://accounts.x.ai/sign-in" have no refresh.
    public static func importCLITokens(json data: Data) -> OAuthTokens? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let entry = (root[modernStorageKey] as? [String: Any])
            ?? (root[legacyStorageKey] as? [String: Any])
        guard let entry else { return nil }

        let accessToken = (entry["key"] as? String)
            ?? (entry["access_token"] as? String)
            ?? (entry["token"] as? String)
        guard let accessToken, !accessToken.isEmpty else { return nil }

        let refreshToken = (entry["refresh_token"] as? String)
            ?? (entry["refresh"] as? String)

        return OAuthTokens(accessToken: accessToken,
                           refreshToken: refreshToken,
                           idToken: nil,
                           accountID: nil,
                           expiresAt: parseExpiresAt(entry["expires_at"]))
    }

    public static func parseExpiresAt(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            guard raw > 0 else { return nil }
            // Epoch milliseconds are > 1e11; epoch seconds this century are < 1e11.
            let seconds = raw > 1e11 ? raw / 1000 : raw
            return Date(timeIntervalSince1970: seconds)
        }
        if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            if let raw = Double(string), raw > 0 {
                let seconds = raw > 1e11 ? raw / 1000 : raw
                return Date(timeIntervalSince1970: seconds)
            }
        }
        return nil
    }

    // MARK: - Wire structs

    private struct ModelsResponse: Decodable {
        struct Model: Decodable {
            let model: String?
            let modelId: String?
            let id: String?
            let hidden: Bool?
        }
        let data: [Model]?
    }

    private struct TokenResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let id_token: String?
        let expires_in: TimeInterval?
    }
}
