import Foundation
import Security

/// Generic-password storage under one keychain service. The app uses `.app`; anything
/// else (tests, screenshots) passes its own service so it never reads the real key.
struct Keychain {
    let service: String

    static let app = Keychain(service: "com.wcoetzee.whatdidisay.keys")

    /// Stores `value`, or deletes the item when it's empty. Returns whether the keychain
    /// now holds what was asked for, so callers can keep a fallback copy when it doesn't.
    @discardableResult
    func set(_ value: String, for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        if status != errSecSuccess {
            NSLog("Keychain write failed: \(SecCopyErrorMessageString(status, nil) as String? ?? "\(status)")")
        }
        return status == errSecSuccess
    }

    func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
