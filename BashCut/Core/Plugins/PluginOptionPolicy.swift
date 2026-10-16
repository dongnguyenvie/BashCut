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

    /// `ownPlugin`: the plugin sets one of its own options over the host channel (#411). It already holds its
    /// credentials, so it may change its non-secret options even when it has secrets; secrets stay user-only.
    public static func validateEdit(options: [PluginOption], author: Author, ownPlugin: Bool = false) throws {
        guard author == .user || (author == .plugin && ownPlugin) || !hasSecrets(options) else {
            throw ProjectError.invalid("Change options for plugins with secrets in Settings")
        }
    }

    /// The checked value of a `plugins.option` call over the host channel (#411): text is read like the command line
    /// (`on`, `12`, a choice), other JSON is checked as it is, and null or a missing value resets to the default (nil).
    /// Secret options are refused: only the user sets them, in Settings.
    public static func ownValue(_ value: JSONValue?, for option: PluginOption) throws -> JSONValue? {
        guard option.type != .secret else {
            throw ProjectError.invalid("A plugin cannot set its secret option \(option.id); the user sets it in Settings")
        }
        switch value {
        case nil, .null?: return nil
        case .string(let text)?: return try option.parse(text)
        case let value?: return try option.check(value)
        }
    }

    /// The options a manifest marks `bindsSecrets` identify where its keys go. Preserve keys for separate
    /// destinations, but never fall back to an old, unbound stored key after an upgrade. Nil when none bind.
    public static func secretBinding(options: [PluginOption], userValues: [String: JSONValue]) -> String? {
        let binding = options.filter { $0.bindsSecrets == true && $0.type != .secret }
        guard !binding.isEmpty else { return nil }
        let fields = binding.map { option -> String in
            let value = userValues[option.id].flatMap { try? option.check($0) } ?? option.fallback
            return option.id + "=" + (value.string ?? String(describing: value))
        }
        // Length prefixes avoid collisions between value pairs without exposing either in secret store keys.
        let body = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
