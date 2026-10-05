import BashCutPlugin
import BashCutPlugins
import Foundation

extension PluginCategory {
    var title: String {
        switch self {
        case .agents: String(localized: "Agents")
        case .captions: String(localized: "Captions")
        case .voice: String(localized: "Voice")
        case .audio: String(localized: "Audio")
        case .color: String(localized: "Color")
        case .effects: String(localized: "Effects")
        case .export: String(localized: "Export")
        case .utilities: String(localized: "Utilities")
        }
    }
}

extension PluginSection {
    var title: String {
        switch kind {
        case .updates: String(localized: "Updates Available")
        case .attention: String(localized: "Needs Attention")
        case .category(let category): category.title
        }
    }

    var symbol: String {
        switch kind {
        case .updates: "arrow.down.circle"
        case .attention: "exclamationmark.triangle"
        case .category(let category): category.symbol
        }
    }
}

/// Categories: what Browse filters by and Installed and Settings group by.
extension PluginManagerModel {
    /// The registry listing's category, else the manifest's, else a guess from the plugin's capabilities.
    func category(of plugin: InstalledPlugin) -> PluginCategory {
        PluginCategory.of(plugin.manifest, listed: registry?.entry(plugin.id)?.category)
    }

    func needsAttention(_ plugin: InstalledPlugin) -> Bool {
        (availability[plugin.id] ?? .untrusted).needsAttention(health: health[plugin.id])
    }

    /// The Installed tab: Updates Available, then Needs Attention, then the rest by category.
    var installedSections: [PluginSection<InstalledPlugin>] {
        let updating = Set(updates.map(\.id))
        return PluginSection.installed(
            plugins, updating: { updating.contains($0.id) }, needsAttention: needsAttention, category: category(of:))
    }
}
