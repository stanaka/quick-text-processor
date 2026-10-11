import Foundation
import QTPCore
import Security

/// Minimal Keychain wrapper for the app's secrets:
/// - API keys:      service "com.stanaka.QuickTextProcessor.apikey"
/// - OAuth tokens:  service "com.stanaka.QuickTextProcessor.oauth" (JSON)
/// Account = provider profile UUID. Nothing here is ever synced to iCloud.
enum Keychain {

    private static let apiKeyService = "com.stanaka.QuickTextProcessor.apikey"
    private static let oauthService = "com.stanaka.QuickTextProcessor.oauth"

    // MARK: - Generic get/set/delete

    static func set(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func get(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - API keys

    static func apiKey(profileID: UUID) -> String? {
        get(service: apiKeyService, account: profileID.uuidString)
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    static func setAPIKey(_ key: String, profileID: UUID) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(service: apiKeyService, account: profileID.uuidString)
        } else {
            set(Data(trimmed.utf8), service: apiKeyService, account: profileID.uuidString)
        }
    }

    // MARK: - OAuth tokens

    static func oauthTokens(profileID: UUID) -> OAuthTokens? {
        guard let data = get(service: oauthService, account: profileID.uuidString) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OAuthTokens.self, from: data)
    }

    static func setOAuthTokens(_ tokens: OAuthTokens, profileID: UUID) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tokens) else { return }
        set(data, service: oauthService, account: profileID.uuidString)
    }

    static func deleteOAuthTokens(profileID: UUID) {
        delete(service: oauthService, account: profileID.uuidString)
    }

    /// Removes every secret belonging to a profile (on profile deletion).
    static func purge(profileID: UUID) {
        delete(service: apiKeyService, account: profileID.uuidString)
        delete(service: oauthService, account: profileID.uuidString)
    }
}
