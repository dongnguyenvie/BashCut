import Foundation

extension PluginOption {
    /// True for a secret the plugin checks before Settings saves it (`check`, host feature `options.check`).
    public var isChecked: Bool { type == .secret && check == true }

    func validateBounds() throws {
        if type == .secret, effectiveScope != .user || defaultValue != nil {
            throw PluginError.invalid("Secret option \(id) must have user scope and no default")
        }
        if check == true, type != .secret {
            throw PluginError.invalid("Option \(id) check is for secret options")
        }
        if bindsSecrets == true, type == .secret || type == .file {
            throw PluginError.invalid("Option \(id) cannot bind secrets: use a string, enum, number or bool option")
        }
        if let minimum, let maximum, minimum > maximum {
            throw PluginError.invalid("Option \(id) minimum is above its maximum")
        }
        if let maxLength, !(1...100_000).contains(maxLength) {
            throw PluginError.invalid("Option \(id) maxLength must be 1...100000")
        }
    }
}

/// A plugin's answer to `options.check`: whether the value works, and a short line saying why.
public struct PluginOptionCheck: Sendable, Equatable {
    public let ok: Bool
    public let message: String?

    public init(ok: Bool, message: String?) {
        self.ok = ok
        self.message = message
    }
}
