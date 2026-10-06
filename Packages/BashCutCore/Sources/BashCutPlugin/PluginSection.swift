import Foundation

/// A run of plugins in a list: one category, or a status section such as Updates Available. Plugins › Browse,
/// Installed and Settings build their lists from these.
public struct PluginSection<Item>: Identifiable {
    public enum Kind: Hashable, Sendable {
        case updates
        case attention
        case category(PluginCategory)
    }

    public let kind: Kind
    public let items: [Item]

    public init(_ kind: Kind, items: [Item]) {
        self.kind = kind
        self.items = items
    }

    public var id: String {
        switch kind {
        case .updates: "updates"
        case .attention: "attention"
        case .category(let category): category.rawValue
        }
    }

    /// `items` split by category, in category order, leaving out empty ones. Items keep their order.
    public static func byCategory(_ items: [Item], category: (Item) -> PluginCategory) -> [PluginSection] {
        let grouped = Dictionary(grouping: items, by: category)
        return PluginCategory.allCases.compactMap { category in
            grouped[category].map { PluginSection(.category(category), items: $0) }
        }
    }

    /// The Installed tab: Updates Available, then Needs Attention, then the rest by category. Each item shows once,
    /// in the first section it belongs to.
    public static func installed(
        _ items: [Item], updating: (Item) -> Bool, needsAttention: (Item) -> Bool, category: (Item) -> PluginCategory
    ) -> [PluginSection] {
        var sections: [PluginSection] = []
        let updates = items.filter(updating)
        let attention = items.filter { !updating($0) && needsAttention($0) }
        if !updates.isEmpty { sections.append(PluginSection(.updates, items: updates)) }
        if !attention.isEmpty { sections.append(PluginSection(.attention, items: attention)) }
        let rest = items.filter { !updating($0) && !needsAttention($0) }
        return sections + byCategory(rest, category: category)
    }
}

extension PluginAvailability {
    /// Whether the plugin needs the user: not trusted, changed, made for another BashCut, or (when ready) missing a
    /// dependency. Turned off is the user's choice, not a problem.
    public func needsAttention(health: PluginHealth?) -> Bool {
        switch self {
        case .ready: health?.state == .degraded
        case .disabled: false
        case .untrusted, .changed, .outdated, .needsPlugin: true
        }
    }
}

extension PluginRegistryEntry {
    /// True when the entry matches a search text, provides `capability` and is in `category` (nil matches any).
    public func matches(_ query: String, capability: String?, category: PluginCategory?) -> Bool {
        matches(query) && (capability.map { (capabilities ?? []).contains($0) } ?? true)
            && (category.map { pluginCategory == $0 } ?? true)
    }
}
