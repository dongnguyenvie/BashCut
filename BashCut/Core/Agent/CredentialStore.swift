import Foundation
import Security

public actor CredentialStore {
    public init() {}
    public func read(account: String) throws -> String {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
            let key = String(data: data, encoding: .utf8)
        else {
            throw ModelError.invalid("Cannot read the API key from Keychain (\(status))")
        }
        return key
    }
    public func save(_ key: String, account: String) throws {
        let query = base(account)
        if key.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else {
                throw ModelError.invalid("Cannot save API key (\(result))")
            }
        } else if update != errSecSuccess {
            throw ModelError.invalid("Cannot update API key (\(update))")
        }
    }
    private func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.bashcut.model-api",
            kSecAttrAccount as String: account,
        ]
    }
}
