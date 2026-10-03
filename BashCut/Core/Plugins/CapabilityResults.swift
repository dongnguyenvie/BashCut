import BashCutPlugin
import BashCutProject
import Foundation

/// Plugin, provider and version that produced a result. Stored as provenance, never as a live dependency.
public struct PluginProvenance: Sendable, Equatable {
    public let pluginID: String
    public let pluginVersion: String
    public let providerID: String

    public init(pluginID: String, pluginVersion: String, providerID: String) {
        self.pluginID = pluginID
        self.pluginVersion = pluginVersion
        self.providerID = providerID
    }

    init(_ resolved: ResolvedPluginProvider) {
        self.init(
            pluginID: resolved.plugin.id, pluginVersion: resolved.plugin.manifest.version,
            providerID: resolved.provider.id)
    }

    public var json: [String: JSONValue] {
        ["plugin": .string(pluginID), "provider": .string(providerID), "version": .string(pluginVersion)]
    }
}

public struct GeneratedPluginAsset: Sendable {
    public let url: URL
    public let provenance: PluginProvenance
}

public struct GeneratedVoiceTake: Identifiable, Sendable {
    public let asset: GeneratedPluginAsset
    public let durationSeconds: Double
    public let score: Double
    public let scoreSource: String
    public var id: String { asset.url.path }
}

public struct GeneratedPluginCaptions: Sendable {
    public let text: String
    public let provenance: PluginProvenance
    /// Word timings in media seconds, when the provider returned a `wordsPath`.
    public var words: [CaptionWords.Timed] = []
}

public struct GeneratedBeatGrid: Sendable {
    public let bpm: Double
    public let beatSeconds: [Double]
    public let provenance: PluginProvenance
}

public struct GeneratedLoudnessMeasurement: Sendable {
    public let measurement: LoudnessMeasurement
    public let provenance: PluginProvenance
}

public extension Array where Element == GeneratedVoiceTake {
    /// Highest score wins; equal scores prefer the earlier take so the choice is deterministic.
    var best: GeneratedVoiceTake? {
        enumerated().max { lhs, rhs in
            lhs.element.score == rhs.element.score ? lhs.offset > rhs.offset : lhs.element.score < rhs.element.score
        }?.element
    }
}
