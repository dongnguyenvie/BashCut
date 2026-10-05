import Foundation

/// The fixed plugin categories that Plugins › Browse, Installed and Settings group by, in display order. The ids
/// match `CATEGORIES` in the registry's `scripts/plugin_manifest.py`, which rejects any other id. A plugin with no
/// category, or one this BashCut does not know, is shown under Utilities.
public enum PluginCategory: String, CaseIterable, Sendable, Identifiable, Comparable {
    case agents, captions, voice, audio, color, effects, export, utilities

    public var id: String { rawValue }

    /// The category named by `id`, or Utilities for a missing or unknown one.
    public init(id: String?) {
        self = id.flatMap(Self.init(rawValue:)) ?? .utilities
    }

    /// The SF Symbol shown next to the category's name.
    public var symbol: String {
        switch self {
        case .agents: "sparkles"
        case .captions: "captions.bubble"
        case .voice: "waveform.and.mic"
        case .audio: "waveform"
        case .color: "camera.filters"
        case .effects: "wand.and.stars"
        case .export: "square.and.arrow.up"
        case .utilities: "wrench.and.screwdriver"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// A plugin's category: the registry listing's, else its manifest's, else a guess from what it provides.
    public static func of(_ manifest: PluginManifest, listed: String? = nil) -> PluginCategory {
        for id in [listed, manifest.category] {
            if let id, let category = PluginCategory(rawValue: id) { return category }
        }
        return inferred(capabilities: manifest.capabilities + (manifest.providers ?? []).map(\.capability))
    }

    /// The category of the first capability with an obvious one; Utilities otherwise.
    static func inferred(capabilities: [String]) -> PluginCategory {
        for capability in capabilities {
            switch capability.split(separator: ".").first {
            case "agent": return .agents
            case "captions": return .captions
            case "voice": return .voice
            case "audio": return .audio
            default: continue
            }
        }
        return .utilities
    }
}

extension PluginRegistryEntry {
    /// The listing's category, or a guess from its capabilities when it names none this BashCut knows.
    public var pluginCategory: PluginCategory {
        category.flatMap(PluginCategory.init(rawValue:)) ?? .inferred(capabilities: capabilities ?? [])
    }
}
