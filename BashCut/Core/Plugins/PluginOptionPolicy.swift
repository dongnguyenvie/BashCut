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

    /// The options a manifest marks `bindsSecrets` identify where its keys go. Preserve keys for separate
    /// destinations, but never fall back to an old, unbound Keychain entry after an upgrade. Nil when none bind.
    public static func secretBinding(options: [PluginOption], userValues: [String: JSONValue]) -> String? {
        let binding = options.filter { $0.bindsSecrets == true && $0.type != .secret }
        guard !binding.isEmpty else { return nil }
        let fields = binding.map { option -> String in
            let value = userValues[option.id].flatMap { try? option.check($0) } ?? option.fallback
            return option.id + "=" + (value.string ?? String(describing: value))
        }
        // Length prefixes avoid collisions between value pairs without exposing either in Keychain IDs.
        let body = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
