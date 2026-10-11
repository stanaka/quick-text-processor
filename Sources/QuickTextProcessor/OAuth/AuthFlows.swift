import AppKit
import Foundation
import QTPCore

enum AuthFlowError: Error, LocalizedError {
    case portUnavailable(UInt16, String)
    case timedOut
    case stateMismatch
    case authorizationFailed(String)
    case tokenExchangeFailed(String)
    case cliCredentialsNotFound(String)
    case cliCredentialsUnreadable(String)
    case notAnOAuthProvider

    var errorDescription: String? {
        switch self {
        case .portUnavailable(let port, let hint):
            return "Could not open localhost port \(port) for the sign-in redirect. \(hint)"
        case .timedOut:
            return "Sign-in timed out — the browser never redirected back."
        case .stateMismatch:
            return "The sign-in redirect did not match this session (state mismatch). Try again."
        case .authorizationFailed(let message):
            return "Sign-in was not authorized: \(message)"
        case .tokenExchangeFailed(let message):
            return "Could not exchange the sign-in code for tokens: \(message)"
        case .cliCredentialsNotFound(let path):
            return "No CLI credentials found at \(path). Log in with the CLI first."
        case .cliCredentialsUnreadable(let path):
            return "The credentials file at \(path) could not be parsed."
        case .notAnOAuthProvider:
            return "This provider uses an API key, not OAuth sign-in."
        }
    }
}

enum AuthPages {
    static let successHTML: String = {
        if let url = Bundle.module.url(forResource: "oauth_success", withExtension: "html"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            return contents
        }
        return """
        <html><body style="font-family:-apple-system,sans-serif;text-align:center;padding-top:4em">
        <h2>Signed in ✓</h2><p>You can close this tab and return to QuickTextProcessor.</p>
        </body></html>
        """
    }()
}

/// Browser PKCE sign-in against auth.openai.com, matching the Codex CLI:
/// fixed localhost port 1455, then a code→token exchange.
enum CodexAuthFlow {

    @MainActor
    static func signIn() async throws -> OAuthTokens {
        let verifier = PKCE.codeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)
        let state = PKCE.state()
        guard let authorizeURL = CodexWire.authorizeURL(challenge: challenge, state: state) else {
            throw AuthFlowError.authorizationFailed("Could not build the authorization URL.")
        }

        let server: LoopbackServer
        do {
            server = try await LoopbackServer.start(port: CodexWire.redirectPort,
                                                    path: CodexWire.redirectPath,
                                                    expectedState: state,
                                                    successHTML: AuthPages.successHTML)
        } catch let error as AuthFlowError {
            throw error
        } catch {
            throw AuthFlowError.portUnavailable(
                CodexWire.redirectPort,
                "The Codex flow requires port 1455 — quit any running `codex login` and try again.")
        }
        defer { server.stop() }

        NSWorkspace.shared.open(authorizeURL)
        let code = try await server.waitForCode()

        let request = CodexWire.tokenExchangeRequest(code: code, verifier: verifier)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200, let tokens = CodexWire.tokens(fromTokenResponse: data) else {
            throw AuthFlowError.tokenExchangeFailed(
                OpenAICompatWire.errorMessage(status: status, body: data))
        }
        return tokens
    }
}

/// Browser PKCE sign-in against auth.x.ai, matching the grok CLI: preferred
/// loopback port 56121 with nearby fallbacks (the redirect URI carries
/// whichever port actually bound).
enum XAIAuthFlow {

    private static let candidatePorts: [UInt16] = [XAIWire.preferredPort, 56122, 56123, 56124, 56125]

    @MainActor
    static func signIn() async throws -> OAuthTokens {
        let verifier = PKCE.codeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)
        let state = PKCE.state()
        let nonce = PKCE.state()

        var server: LoopbackServer?
        for port in candidatePorts {
            if let bound = try? await LoopbackServer.start(port: port,
                                                           path: XAIWire.redirectPath,
                                                           expectedState: state,
                                                           successHTML: AuthPages.successHTML) {
                server = bound
                break
            }
        }
        guard let server else {
            throw AuthFlowError.portUnavailable(
                XAIWire.preferredPort,
                "Ports \(candidatePorts.first!)–\(candidatePorts.last!) are all in use.")
        }
        defer { server.stop() }

        let redirectURI = XAIWire.redirectURI(port: server.port)
        guard let authorizeURL = XAIWire.authorizeURL(challenge: challenge,
                                                      state: state,
                                                      nonce: nonce,
                                                      redirectURI: redirectURI) else {
            throw AuthFlowError.authorizationFailed("Could not build the authorization URL.")
        }

        NSWorkspace.shared.open(authorizeURL)
        let code = try await server.waitForCode()

        let request = XAIWire.tokenExchangeRequest(code: code,
                                                   verifier: verifier,
                                                   redirectURI: redirectURI)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200, let tokens = XAIWire.tokens(fromTokenResponse: data) else {
            throw AuthFlowError.tokenExchangeFailed(
                OpenAICompatWire.errorMessage(status: status, body: data))
        }
        return tokens
    }
}
