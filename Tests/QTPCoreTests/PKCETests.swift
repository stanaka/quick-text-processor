import XCTest
@testable import QTPCore

final class PKCETests: XCTestCase {

    func testRFC7636Vector() {
        // Appendix B of RFC 7636.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(PKCE.codeChallenge(for: verifier),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testVerifierLengthAndCharset() {
        let verifier = PKCE.codeVerifier()
        XCTAssertEqual(verifier.count, 86) // 64 bytes → 86 base64url chars
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testStateIsHexAndUnique() {
        let a = PKCE.state()
        let b = PKCE.state()
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.allSatisfy { $0.isHexDigit })
    }

    func testJWTPayloadDecode() {
        let jwt = TestJWT.make(payload: [
            "exp": 1_900_000_000,
            "https://api.openai.com/auth": ["chatgpt_account_id": "acc-42"],
        ])
        XCTAssertEqual(JWT.stringClaim(jwt, path: ["https://api.openai.com/auth",
                                                   "chatgpt_account_id"]), "acc-42")
        XCTAssertEqual(JWT.expiration(jwt),
                       Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertNil(JWT.payload("garbage"))
        XCTAssertNil(JWT.stringClaim(jwt, path: ["missing"]))
    }

    func testFormBodyEncoding() {
        let data = FormBody.encode([("a b", "c&d"), ("e", "f=g")])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "a%20b=c%26d&e=f%3Dg")
    }
}

/// Builds unsigned JWTs for tests (header.payload.signature, base64url).
enum TestJWT {
    static func make(payload: [String: Any]) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "none"])
        let body = try! JSONSerialization.data(withJSONObject: payload)
        return [header, body, Data("sig".utf8)]
            .map { data in
                data.base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            }
            .joined(separator: ".")
    }
}
