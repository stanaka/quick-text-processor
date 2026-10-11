import XCTest
@testable import QTPCore

final class ProviderRequestTests: XCTestCase {

    private func json(_ data: Data?) throws -> [String: Any] {
        let unwrapped = try XCTUnwrap(data)
        let object = try JSONSerialization.jsonObject(with: unwrapped)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - openai-compatible

    func testChatCompletionsURLNormalization() {
        let expected = "https://api.openai.com/v1/chat/completions"
        for base in ["https://api.openai.com",
                     "https://api.openai.com/",
                     "https://api.openai.com/v1",
                     "https://api.openai.com/v1/",
                     "  https://api.openai.com \n"] {
            XCTAssertEqual(OpenAICompatWire.chatCompletionsURL(base: base)?.absoluteString,
                           expected, "base=\(base)")
        }
        XCTAssertEqual(OpenAICompatWire.chatCompletionsURL(base: "http://localhost:11434")?.absoluteString,
                       "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(OpenAICompatWire.chatCompletionsURL(base: "   "))
    }

    func testOpenAICompatRequest() throws {
        let request = try OpenAICompatWire.request(baseURL: "https://api.openai.com",
                                                   apiKey: "sk-test",
                                                   model: "gpt-4o-mini",
                                                   prompt: "Fix \"this\"\nplease 😀")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try json(request.httpBody)
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "Fix \"this\"\nplease 😀")
        // The API key must never leak into the body.
        let raw = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertFalse(raw.contains("sk-test"))
    }

    func testModelsURLNormalization() {
        let expected = "https://api.openai.com/v1/models"
        for base in ["https://api.openai.com",
                     "https://api.openai.com/",
                     "https://api.openai.com/v1",
                     "https://api.openai.com/v1/",
                     "  https://api.openai.com \n"] {
            XCTAssertEqual(OpenAICompatWire.modelsURL(base: base)?.absoluteString,
                           expected, "base=\(base)")
        }
        XCTAssertEqual(OpenAICompatWire.modelsURL(base: "http://localhost:11434")?.absoluteString,
                       "http://localhost:11434/v1/models")
        XCTAssertNil(OpenAICompatWire.modelsURL(base: "   "))
    }

    func testModelsRequest() throws {
        let request = try OpenAICompatWire.modelsRequest(baseURL: "https://api.openai.com",
                                                         apiKey: "sk-test")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertNil(request.httpBody)
    }

    func testModelsRequestOmitsAuthorizationWhenKeyEmpty() throws {
        let request = try OpenAICompatWire.modelsRequest(baseURL: "http://localhost:11434",
                                                         apiKey: "")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testModelsRequestRejectsBlankBaseURL() {
        XCTAssertThrowsError(try OpenAICompatWire.modelsRequest(baseURL: "   ", apiKey: "k"))
    }

    func testModelIDsDecoding() {
        let json = #"{"object":"list","data":[{"id":"gpt-4o-mini","object":"model"},{"id":"Aardvark"},{"id":"gpt-4o-mini"},{"id":""}]}"#
        XCTAssertEqual(OpenAICompatWire.modelIDs(fromModelsResponse: Data(json.utf8)),
                       ["Aardvark", "gpt-4o-mini"])
        XCTAssertEqual(OpenAICompatWire.modelIDs(fromModelsResponse: Data("not json".utf8)), [])
        XCTAssertEqual(OpenAICompatWire.modelIDs(fromModelsResponse: Data(#"{"data":[]}"#.utf8)), [])
    }

    // MARK: - codex

    func testCodexChatRequestHeadersAndBody() throws {
        let tokens = OAuthTokens(accessToken: "at-1", refreshToken: "rt-1",
                                 idToken: nil, accountID: "acc-9")
        let request = try CodexWire.chatRequest(tokens: tokens,
                                                model: "gpt-5.2-codex",
                                                prompt: "PROMPT",
                                                instructions: "INSTR")
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/codex/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer at-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), "acc-9")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Beta"), "responses=experimental")
        XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), "codex_cli_rs")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "session_id"))

        let body = try json(request.httpBody)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["instructions"] as? String, "INSTR")
        XCTAssertEqual(body["include"] as? [String], ["reasoning.encrypted_content"])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input[0]["role"] as? String, "user")
        let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "input_text")
        XCTAssertEqual(content[0]["text"] as? String, "PROMPT")
    }

    func testCodexChatRequestRequiresAccountID() {
        let tokens = OAuthTokens(accessToken: "at", accountID: nil)
        XCTAssertThrowsError(try CodexWire.chatRequest(tokens: tokens, model: "m",
                                                       prompt: "p", instructions: "i"))
    }

    func testCodexAuthorizeURL() throws {
        let url = try XCTUnwrap(CodexWire.authorizeURL(challenge: "CH", state: "ST"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "auth.openai.com")
        XCTAssertEqual(components.path, "/oauth/authorize")
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value }
        XCTAssertEqual(query["client_id"], CodexWire.clientID)
        XCTAssertEqual(query["code_challenge"], "CH")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["state"], "ST")
        XCTAssertEqual(query["redirect_uri"], "http://localhost:1455/auth/callback")
        XCTAssertEqual(query["response_type"], "code")
    }

    func testCodexTokenExchangeBody() {
        let request = CodexWire.tokenExchangeRequest(code: "the code", verifier: "ver")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=the%20code"))
        XCTAssertTrue(body.contains("code_verifier=ver"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
    }

    func testCodexModelsRequest() throws {
        let tokens = OAuthTokens(accessToken: "at-1", refreshToken: "rt-1",
                                 idToken: nil, accountID: "acc-9")
        let request = try CodexWire.modelsRequest(tokens: tokens, clientVersion: "0.1.0")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://chatgpt.com/backend-api/codex/models?client_version=0.1.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer at-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), "acc-9")
        XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), "codex_cli_rs")
        XCTAssertNil(request.httpBody)
    }

    func testCodexModelsRequestRequiresAccountID() {
        let tokens = OAuthTokens(accessToken: "at", accountID: nil)
        XCTAssertThrowsError(try CodexWire.modelsRequest(tokens: tokens, clientVersion: "0.1.0"))
    }

    func testCodexModelIDsDecoding() {
        let json = #"""
        {"models":[
            {"slug":"gpt-b","display_name":"B","visibility":"list","priority":7},
            {"slug":"gpt-hidden","visibility":"hide","priority":1},
            {"slug":"gpt-a","visibility":"list","priority":1},
            {"slug":"gpt-none","visibility":"none","priority":2},
            {"slug":"gpt-noprio","visibility":"list"}
        ]}
        """#
        XCTAssertEqual(CodexWire.modelIDs(fromModelsResponse: Data(json.utf8)),
                       ["gpt-a", "gpt-b", "gpt-noprio"])
        XCTAssertEqual(CodexWire.modelIDs(fromModelsResponse: Data("not json".utf8)), [])
        XCTAssertEqual(CodexWire.modelIDs(fromModelsResponse: Data(#"{"models":[]}"#.utf8)), [])
    }

    // MARK: - xai

    func testXAIChatRequestHeadersAndBody() throws {
        let tokens = OAuthTokens(accessToken: "xt-1")
        let request = try XAIWire.chatRequest(tokens: tokens,
                                              model: "grok-4.6",
                                              prompt: "PROMPT",
                                              clientVersion: "0.1.0")
        XCTAssertEqual(request.url?.absoluteString, "https://cli-chat-proxy.grok.com/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xt-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-client-identifier"), "quick-text-processor")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-client-version"), "0.1.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-authenticateresponse"), "authenticate-response")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-client-mode"), "interactive")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-model-override"), "grok-4.6")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-grok-conv-id"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-grok-req-id"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-grok-session-id"))

        let body = try json(request.httpBody)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNil(body["instructions"])
        XCTAssertEqual(body["model"] as? String, "grok-4.6")
    }

    func testXAIAuthorizeURLIncludesNonceAndCustomPort() throws {
        let redirect = XAIWire.redirectURI(port: 56122)
        let url = try XCTUnwrap(XAIWire.authorizeURL(challenge: "CH", state: "ST",
                                                     nonce: "NO", redirectURI: redirect))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value }
        XCTAssertEqual(components.host, "auth.x.ai")
        XCTAssertEqual(query["nonce"], "NO")
        XCTAssertEqual(query["redirect_uri"], "http://127.0.0.1:56122/callback")
        XCTAssertEqual(query["client_id"], XAIWire.clientID)
    }

    func testXAIModelsRequest() throws {
        let tokens = OAuthTokens(accessToken: "xt-1")
        let request = try XAIWire.modelsRequest(tokens: tokens, clientVersion: "0.1.0")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://cli-chat-proxy.grok.com/v1/models-v2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xt-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-client-identifier"),
                       "quick-text-processor")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-grok-model-override"))
        XCTAssertNil(request.httpBody)
    }

    func testXAIModelIDsDecoding() {
        let json = #"""
        {"data":[
            {"model":"m1","name":"M1"},
            {"model":"m2","hidden":true},
            {"modelId":"m3"},
            {"id":"m4"},
            {"model":"m1"},
            {"name":"no-id"}
        ]}
        """#
        XCTAssertEqual(XAIWire.modelIDs(fromModelsResponse: Data(json.utf8)),
                       ["m1", "m3", "m4"])
        XCTAssertEqual(XAIWire.modelIDs(fromModelsResponse: Data("not json".utf8)), [])
        XCTAssertEqual(XAIWire.modelIDs(fromModelsResponse: Data(#"{"data":[]}"#.utf8)), [])
    }

    // MARK: - fallback candidates

    func testFallbackModelCandidates() {
        XCTAssertTrue(CodexWire.fallbackModelCandidates.contains(ProviderType.codexOAuth.defaultModel))
        XCTAssertTrue(XAIWire.fallbackModelCandidates.contains(ProviderType.xaiOAuth.defaultModel))
        XCTAssertEqual(CodexWire.fallbackModelCandidates.count,
                       Set(CodexWire.fallbackModelCandidates).count)
        XCTAssertEqual(XAIWire.fallbackModelCandidates.count,
                       Set(XAIWire.fallbackModelCandidates).count)
    }
}
