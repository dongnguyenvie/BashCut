import Foundation
import Security

/// Values of `secret` plugin options (API keys), kept in the Keychain under service `app.bashcut.plugin-secret`
/// and account `<plugin id>/<option id>/endpoint/<binding>` for endpoint-bound keys. They are never shown, listed
/// or logged. Tests use an in-memory store.
public final class PluginSecretStore: @unchecked Sendable {
    public static let service = "app.bashcut.plugin-secret"
    private let keychain: Bool
    private let lock = NSLock()
    private var memory: [String: String] = [:]

    public init(keychain: Bool = true) { self.keychain = keychain }

    public func read(plugin: String, option: String, binding: String? = nil) -> String {
        let account = Self.account(plugin, option, binding: binding)
        lock.lock()
        defer { lock.unlock() }
        if let cached = memory[account] { return cached }
        guard keychain else { return "" }
        var query = Self.query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let value = SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
            ? (result as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "" : ""
        memory[account] = value
        return value
    }

    /// Stores `value`; an empty value deletes the secret.
    public func write(_ value: String, plugin: String, option: String, binding: String? = nil) throws {
        let account = Self.account(plugin, option, binding: binding)
        lock.lock()
        defer { lock.unlock() }
        if keychain {
            let query = Self.query(account)
            SecItemDelete(query as CFDictionary)
            if !value.isEmpty {
                var item = query
                item[kSecValueData as String] = Data(value.utf8)
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                let status = SecItemAdd(item as CFDictionary, nil)
                guard status == errSecSuccess else {
                    throw CocoaError(.fileWriteUnknown, userInfo: [
                        NSLocalizedDescriptionKey: "Cannot save the secret in the Keychain (\(status))",
                    ])
                }
            }
        }
        memory[account] = value
    }

    private static func account(_ plugin: String, _ option: String, binding: String?) -> String {
        plugin + "/" + option + (binding.map { "/endpoint/" + $0 } ?? "")
    }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
