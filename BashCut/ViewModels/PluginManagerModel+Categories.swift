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

/// A titled run of plugins in a list: one category, or a status section such as Updates Available.
struct PluginGroup<Item>: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let items: [Item]

    init(_ category: PluginCategory, items: [Item]) {
        id = category.rawValue
        title = category.title
        symbol = category.symbol
        self.items = items
    }

    init(id: String, title: String, symbol: String, items: [Item]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.items = items
    }

    /// `items` split by category, in category order, leaving out empty ones.
    static func byCategory(_ items: [Item], category: (Item) -> PluginCategory) -> [PluginGroup] {
        let grouped = Dictionary(grouping: items, by: category)
        return PluginCategory.allCases.compactMap { category in
            grouped[category].map { PluginGroup(category, items: $0) }
        }
    }
}

/// Categories: what Browse filters by and Installed and Settings group by.
extension PluginManagerModel {
    /// The registry listing's category, else the manifest's, else a guess from the plugin's capabilities.
    func category(of plugin: InstalledPlugin) -> PluginCategory {
        PluginCategory.of(plugin.manifest, listed: registry?.entry(plugin.id)?.category)
    }

    /// Not trusted, changed, made for another BashCut, or missing a dependency. Turned off is the user's choice.
    func needsAttention(_ plugin: InstalledPlugin) -> Bool {
        switch availability[plugin.id] ?? .untrusted {
        case .ready: health[plugin.id]?.state == .degraded
        case .disabled: false
        case .untrusted, .changed, .outdated: true
        }
    }

    /// The Installed tab: Updates Available, then Needs Attention, then the rest by category. A plugin shows once.
    var installedGroups: [PluginGroup<InstalledPlugin>] {
        let updating = Set(updates.map(\.id))
        let updates = plugins.filter { updating.contains($0.id) }
        let attention = plugins.filter { !updating.contains($0.id) && needsAttention($0) }
        let listed = Set((updates + attention).map(\.id))
        var groups: [PluginGroup<InstalledPlugin>] = []
        if !updates.isEmpty {
            groups.append(PluginGroup(
                id: "updates", title: String(localized: "Updates Available"), symbol: "arrow.down.circle", items: updates))
        }
        if !attention.isEmpty {
            groups.append(PluginGroup(
                id: "attention", title: String(localized: "Needs Attention"), symbol: "exclamationmark.triangle",
                items: attention))
        }
        return groups + PluginGroup.byCategory(plugins.filter { !listed.contains($0.id) }, category: category(of:))
    }
}
