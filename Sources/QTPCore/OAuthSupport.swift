import CryptoKit
import Foundation

// MARK: - PKCE (RFC 7636)

public enum PKCE {

    /// 86-char base64url verifier from 64 random bytes ([A-Za-z0-9-_]).
    public static func codeVerifier() -> String {
        base64url(randomBytes(64))
    }

    /// S256 challenge: base64url(SHA256(ASCII(verifier))).
    public static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64url(Data(digest))
    }

    /// Random hex state / nonce value.
    public static func state() -> String {
        randomBytes(16).map { String(format: "%02x", $0) }.joined()
    }

    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        for index in data.indices {
            data[index] = UInt8.random(in: .min ... .max)
        }
        return data
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - JWT (decode only; signatures are not verified — the tokens come
// straight from the issuer over TLS and are only inspected for claims)

public enum JWT {

    public static func payload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The "exp" claim as a Date.
    public static func expiration(_ jwt: String) -> Date? {
        guard let exp = payload(jwt)?["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// A string claim at a key path, e.g. ["https://api.openai.com/auth",
    /// "chatgpt_account_id"].
    public static func stringClaim(_ jwt: String, path: [String]) -> String? {
        guard let root = payload(jwt) else { return nil }
        var current: Any = root
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
            current = next
        }
        return current as? String
    }
}

// MARK: - application/x-www-form-urlencoded bodies

public enum FormBody {

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    public static func encode(_ fields: [(String, String)]) -> Data {
        let string = fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        return Data(string.utf8)
    }
}

// MARK: - Loopback redirect parsing (pure part of the local OAuth callback
// server, kept here so it is unit-testable)

public enum LoopbackRequestParser {

    public struct Callback: Equatable {
        public var path: String
        public var query: [String: String]

        public init(path: String, query: [String: String]) {
            self.path = path
            self.query = query
        }
    }

    /// Parses the request line of an HTTP request head
    /// ("GET /callback?code=x&state=y HTTP/1.1\r\n...").
    /// Returns nil for anything that is not a plausible GET request.
    public static func parse(requestHead: String) -> Callback? {
        let firstLine = requestHead.prefix(while: { $0 != "\n" && $0 != "\r" })
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        guard let components = URLComponents(string: String(parts[1])) else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return Callback(path: components.path, query: query)
    }
}
