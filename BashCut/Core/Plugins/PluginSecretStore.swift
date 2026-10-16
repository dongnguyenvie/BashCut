import Foundation

/// Values of `secret` plugin options (API keys) and link access tokens, kept as plain JSON in
/// `~/Library/Application Support/BashCut/plugin-secrets.json` (owner read/write only), keyed by
/// `<credential identity>/<option id>`, plus `/binding/<hash>` when the manifest marks options `bindsSecrets`.
/// Not the Keychain for now: a dev copy signed differently from the release made every read block on a Keychain
/// access prompt. They are never shown, listed or logged. Tests use an in-memory store (`file: nil`).
public final class PluginSecretStore: @unchecked Sendable {
    /// The store next to the user plugin folder, in Application Support/BashCut.
    public static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BashCut/plugin-secrets.json")
    }

    private let file: URL?
    private let lock = NSLock()
    private var memory: [String: String]?

    public init(file: URL? = PluginSecretStore.defaultFile) { self.file = file }

    public func read(plugin: String, option: String, binding: String? = nil) -> String {
        let account = Self.account(plugin, option, binding: binding)
        lock.lock()
        defer { lock.unlock() }
        return loaded()[account] ?? ""
    }

    /// Stores `value`; an empty value deletes the secret.
    public func write(_ value: String, plugin: String, option: String, binding: String? = nil) throws {
        let account = Self.account(plugin, option, binding: binding)
        lock.lock()
        defer { lock.unlock() }
        var all = loaded()
        all[account] = value.isEmpty ? nil : value
        try save(all)
    }

    /// Deletes `option` keys of identities starting with `prefix` other than `identity`: keys entered for an
    /// installation's older code, which can never be read again. Keys for other bindings of `identity` stay.
    public func removeStale(option: String, prefix: String, keeping identity: String) {
        func stale(_ account: String) -> Bool {
            guard account.hasPrefix(prefix), !account.hasPrefix(identity + "/") else { return false }
            let parts = account.dropFirst(prefix.count).split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { return false }
            return parts[1] == option || parts[1].hasPrefix(option + "/")
        }
        lock.lock()
        defer { lock.unlock() }
        let all = loaded()
        let kept = all.filter { !stale($0.key) }
        if kept.count != all.count { try? save(kept) }
    }

    /// Every stored secret, read from the file once. Call with `lock` held.
    private func loaded() -> [String: String] {
        if let memory { return memory }
        let stored = file.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        memory = stored
        return stored
    }

    /// Writes `all` to the file (0600) and the cache. Call with `lock` held.
    private func save(_ all: [String: String]) throws {
        if let file {
            let manager = FileManager.default
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(all).write(to: file, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        memory = all
    }

    private static func account(_ plugin: String, _ option: String, binding: String?) -> String {
        plugin + "/" + option + (binding.map { "/binding/" + $0 } ?? "")
    }
}
