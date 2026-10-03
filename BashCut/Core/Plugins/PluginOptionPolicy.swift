import BashCutPlugin
import BashCutProject
import CryptoKit
import Foundation

/// A project or agent must not redirect a plugin that holds user credentials.
public enum PluginOptionPolicy {
    public static func hasSecrets(_ options: [PluginOption]) -> Bool { options.contains { $0.type == .secret } }

    public static func scope(of option: PluginOption, in options: [PluginOption]) -> PluginOption.Scope {
        hasSecrets(options) ? .user : option.effectiveScope
    }

    public static func validateEdit(options: [PluginOption], author: Author) throws {
        guard author == .user || !hasSecrets(options) else {
            throw ProjectError.invalid("Change options for plugins with secrets in Settings")
        }
    }

    /// Director's provider and compatible endpoint identify the destination of its API key. Preserve keys for
    /// separate endpoints, but never fall back to an old, unbound Keychain entry after an upgrade.
    public static func endpointBinding(options: [PluginOption], userValues: [String: JSONValue]) -> String {
        let fields = ["provider", "baseUrl"].map { key -> String in
            guard let option = options.first(where: { $0.id == key }) else { return "" }
            return (userValues[key].flatMap { try? option.check($0) } ?? option.fallback).string ?? ""
        }
        // Length prefixes avoid collisions between provider/URL pairs without exposing either in Keychain IDs.
        let body = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
