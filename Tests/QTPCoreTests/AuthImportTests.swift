import XCTest
@testable import QTPCore

final class AuthImportTests: XCTestCase {

    // MARK: - Codex CLI (~/.codex/auth.json)

    func testCodexImportWithExplicitAccountID() throws {
        let json = """
        {
          "openai_api_key": null,
          "tokens": {
            "id_token": "\(TestJWT.make(payload: ["exp": 1_900_000_000]))",
            "access_token": "\(TestJWT.make(payload: ["exp": 1_900_000_000]))",
            "refresh_token": "rt-1",
            "account_id": "acc-explicit"
          },
          "last_refresh": "2026-08-01T00:00:00Z"
        }
        """
        let tokens = try XCTUnwrap(CodexWire.importCLITokens(json: Data(json.utf8)))
        XCTAssertEqual(tokens.accountID, "acc-explicit")
        XCTAssertEqual(tokens.refreshToken, "rt-1")
        XCTAssertEqual(tokens.expiresAt, Date(timeIntervalSince1970: 1_900_000_000))
    }

    func testCodexImportExtractsAccountIDFromIDToken() throws {
        let idToken = TestJWT.make(payload: [
            "https://api.openai.com/auth": ["chatgpt_account_id": "acc-jwt"]
        ])
        let json = """
        { "tokens": { "id_token": "\(idToken)", "access_token": "at", "refresh_token": "rt" } }
        """
        let tokens = try XCTUnwrap(CodexWire.importCLITokens(json: Data(json.utf8)))
        XCTAssertEqual(tokens.accountID, "acc-jwt")
    }

    func testCodexImportRejectsGarbage() {
        XCTAssertNil(CodexWire.importCLITokens(json: Data("{}".utf8)))
        XCTAssertNil(CodexWire.importCLITokens(json: Data("nope".utf8)))
    }

    func testCodexTokenResponseParsing() throws {
        let json = #"{"id_token":null,"access_token":"at-new","refresh_token":"rt-new","expires_in":3600}"#
        let existing = OAuthTokens(accessToken: "old", refreshToken: "rt-old",
                                   idToken: nil, accountID: "acc-1")
        let tokens = try XCTUnwrap(CodexWire.tokens(fromTokenResponse: Data(json.utf8),
                                                    existing: existing))
        XCTAssertEqual(tokens.accessToken, "at-new")
        XCTAssertEqual(tokens.refreshToken, "rt-new")
        // account id carried over from the previous token set
        XCTAssertEqual(tokens.accountID, "acc-1")
        let expires = try XCTUnwrap(tokens.expiresAt)
        XCTAssertEqual(expires.timeIntervalSinceNow, 3600, accuracy: 30)
    }

    func testCodexRefreshKeepsExistingRefreshTokenWhenOmitted() throws {
        let json = #"{"access_token":"at-new"}"#
        let existing = OAuthTokens(accessToken: "old", refreshToken: "rt-old")
        let tokens = try XCTUnwrap(CodexWire.tokens(fromTokenResponse: Data(json.utf8),
                                                    existing: existing))
        XCTAssertEqual(tokens.refreshToken, "rt-old")
    }

    // MARK: - Grok CLI (~/.grok/auth.json)

    func testGrokModernKeyImport() throws {
        let json = """
        {
          "https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828": {
            "access_token": "xa-1",
            "refresh_token": "xr-1",
            "expires_at": 1900000000
          }
        }
        """
        let tokens = try XCTUnwrap(XAIWire.importCLITokens(json: Data(json.utf8)))
        XCTAssertEqual(tokens.accessToken, "xa-1")
        XCTAssertEqual(tokens.refreshToken, "xr-1")
        XCTAssertEqual(tokens.expiresAt, Date(timeIntervalSince1970: 1_900_000_000))
    }

    func testGrokAlternateFieldNames() throws {
        let json = """
        {
          "https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828": {
            "key": "xa-key", "refresh": "xr-alt", "expires_at": 1900000000000
          }
        }
        """
        let tokens = try XCTUnwrap(XAIWire.importCLITokens(json: Data(json.utf8)))
        XCTAssertEqual(tokens.accessToken, "xa-key")
        XCTAssertEqual(tokens.refreshToken, "xr-alt")
        // milliseconds normalized to seconds
        XCTAssertEqual(tokens.expiresAt, Date(timeIntervalSince1970: 1_900_000_000))
    }

    func testGrokLegacyKeyImport() throws {
        let json = """
        { "https://accounts.x.ai/sign-in": { "token": "legacy-token" } }
        """
        let tokens = try XCTUnwrap(XAIWire.importCLITokens(json: Data(json.utf8)))
        XCTAssertEqual(tokens.accessToken, "legacy-token")
        XCTAssertNil(tokens.refreshToken)
    }

    func testGrokExpiresAtVariants() {
        XCTAssertEqual(XAIWire.parseExpiresAt(NSNumber(value: 1_900_000_000)),
                       Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(XAIWire.parseExpiresAt(NSNumber(value: 1_900_000_000_000)),
                       Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(XAIWire.parseExpiresAt("2030-03-15T12:00:00Z"),
                       ISO8601DateFormatter().date(from: "2030-03-15T12:00:00Z"))
        XCTAssertEqual(XAIWire.parseExpiresAt("1900000000"),
                       Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertNil(XAIWire.parseExpiresAt(nil))
        XCTAssertNil(XAIWire.parseExpiresAt("soon"))
    }

    func testGrokImportRejectsUnknownShape() {
        XCTAssertNil(XAIWire.importCLITokens(json: Data("{}".utf8)))
        XCTAssertNil(XAIWire.importCLITokens(json: Data("[1,2]".utf8)))
    }

    // MARK: - needsRefresh

    func testNeedsRefresh() {
        let now = Date()
        XCTAssertFalse(OAuthTokens(accessToken: "a", expiresAt: nil).needsRefresh(now: now))
        XCTAssertTrue(OAuthTokens(accessToken: "a", expiresAt: now.addingTimeInterval(60))
            .needsRefresh(leeway: 300, now: now))
        XCTAssertFalse(OAuthTokens(accessToken: "a", expiresAt: now.addingTimeInterval(3600))
            .needsRefresh(leeway: 300, now: now))
    }
}
