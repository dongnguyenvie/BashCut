import BashCutPlugin
import BashCutProject
import Foundation

/// Option checks (`options.check`): a plugin says whether a secret works before Settings saves it.
extension CapabilityService {
    /// Asks a ready plugin whether `value` is right for its `secret` option `option` before Settings saves it
    /// (`options.check`, host feature `options.check`). `options` are the plugin's current values with this one
    /// replaced, so a plugin can check the key against the chosen service. A plugin that cannot answer, or answers
    /// something else, gives `nil`.
    public func checkOption(
        _ option: String, value: String, options: [String: JSONValue], plugin: InstalledPlugin
    ) async -> PluginOptionCheck? {
        guard availability(plugin) == .ready else { return nil }
        var values = options
        values[option] = .string(value)
        let params: JSONValue = .object(["option": .string(option), "value": .string(value), "options": .object(values)])
        guard let answer = try? await transport.call(
            plugin: plugin, method: "options.check", provider: nil, params: params, progress: nil),
            case .bool(let ok)? = answer.object["ok"]
        else { return nil }
        let message = answer.object["message"]?.string.map { String($0.prefix(300)) }
        return PluginOptionCheck(ok: ok, message: message?.isEmpty == false ? message : nil)
    }
}
