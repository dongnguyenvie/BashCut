import Foundation

public struct ResolvedPluginProvider: Sendable, Equatable {
    public let plugin: InstalledPlugin
    public let provider: PluginProvider

    public init(plugin: InstalledPlugin, provider: PluginProvider) {
        self.plugin = plugin
        self.provider = provider
    }
}

public enum PluginProviderResolver {
    /// Preferences are hints. An unavailable project choice falls back to the user choice, then priority.
    public static func resolve(
        capability: String, projectPreference: String?, userPreference: String?,
        plugins: [InstalledPlugin], availableProviderIDs: Set<String>
    ) -> ResolvedPluginProvider? {
        let candidates = plugins.flatMap { plugin in
            (plugin.manifest.providers ?? []).filter { provider in
                provider.capability == capability && availableProviderIDs.contains(provider.id)
            }.map { ResolvedPluginProvider(plugin: plugin, provider: $0) }
        }
        for preference in [projectPreference, userPreference].compactMap({ $0 }) {
            if let match = candidates.first(where: { $0.provider.id == preference }) { return match }
        }
        return candidates.sorted {
            ($0.provider.priority, $0.provider.id) > ($1.provider.priority, $1.provider.id)
        }.first
    }
}
