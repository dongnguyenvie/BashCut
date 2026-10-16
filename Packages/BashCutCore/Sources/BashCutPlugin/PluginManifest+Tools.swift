import Foundation

extension PluginManifest {
    /// What APIs 9, 10, 11 and 12 added to the manifest.
    func validateLatestAPI() throws {
        try validatePlatformTable()
        try validateTools()
        try validateExportSteps()
        guard !views.contains(where: { $0.place == .window }) || apiVersion >= 11 else {
            throw PluginError.invalid("location window needs apiVersion 11")
        }
    }

    /// The platform table file (plugin API 9): a relative path inside the plugin.
    func validatePlatformTable() throws {
        guard let path = contributes?.platforms else { return }
        guard apiVersion >= 9 else { throw PluginError.invalid("contributes.platforms needs apiVersion 9") }
        let components = NSString(string: path).pathComponents
        guard path.hasSuffix(".json"), path.count <= 512, !path.hasPrefix("/"), !path.hasPrefix("~"),
            !components.contains("..")
        else { throw PluginError.invalid("contributes.platforms must be a .json file inside the plugin bundle") }
    }

    /// The Tools panel (plugin API 10): the `tools` placement, `kind: tool` views and `advanced` options.
    func validateTools() throws {
        let usesTools = actions.contains { $0.isTool || ($0.params ?? []).contains { $0.isAdvanced } }
            || views.contains { $0.kind != nil }
        guard !usesTools || apiVersion >= 10 else {
            throw PluginError.invalid("The tools placement, view kind and advanced options need apiVersion 10")
        }
    }
}
