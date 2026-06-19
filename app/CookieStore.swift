import Foundation
import Security

// MARK: - Secure cookie storage (Keychain)
//
// The session cookie is full claude.ai account auth, so it belongs in the
// Keychain — not UserDefaults, where it sat in a plaintext plist. Generic
// password item; no entitlement needed since the app isn't sandboxed.
enum CookieStore {
    // Derive the Keychain service from the actual bundle identifier so a fork
    // built under a different CFBundleIdentifier gets its own item automatically
    // (no second hard-coded string to keep in sync). Falls back to the canonical
    // id when running outside an app bundle, e.g. a bare test binary.
    private static let service = Bundle.main.bundleIdentifier ?? "com.claudometer.app"
    private static let account = "claude_session_cookie"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ cookie: String) {
        let data = Data(cookie.utf8)
        if SecItemCopyMatching(baseQuery as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(baseQuery as CFDictionary,
                          [kSecValueData as String: data] as CFDictionary)
        } else {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
