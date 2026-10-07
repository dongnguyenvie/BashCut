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
    /// Grid v2 facts the provider gave (P0-B10), checked: strengths, downbeats, beatsPerBar, phaseScores,
    /// confidence, fit, alternates. Empty for a provider that gives only beats.
    public var grid: [String: JSONValue] = [:]
}

/// `audio.energy` (P0-B10): level, onset density and fullness every `step` seconds, and lift/drop/breath candidates.
public struct GeneratedEnergy: Sendable {
    public let result: JSONValue
    public let provenance: PluginProvenance
}

public struct GeneratedLoudnessMeasurement: Sendable {
    public let measurement: LoudnessMeasurement
    public let provenance: PluginProvenance
}

public struct GeneratedAudioSync: Sendable {
    public struct Match: Sendable, Equatable {
        /// Time in the other file = time in the first + `offsetSeconds`.
        public let offsetSeconds: Double
        public let correlation: Double
    }

    public let match: Match
    /// The match of each half of the overlap; agreeing halves mean no clock drift.
    public let halves: [Match]
    /// The overlap in the first file's time, when the provider reports it.
    public let overlap: ClosedRange<Double>?
    public let provenance: PluginProvenance

    /// The halves agree within 0.02 s.
    public var isSteady: Bool {
        halves.count == 2 && abs(halves[0].offsetSeconds - halves[1].offsetSeconds) <= 0.020_001
    }
}

public extension Array where Element == GeneratedVoiceTake {
    /// Highest score wins; equal scores prefer the earlier take so the choice is deterministic.
    var best: GeneratedVoiceTake? {
        enumerated().max { lhs, rhs in
            lhs.element.score == rhs.element.score ? lhs.offset > rhs.offset : lhs.element.score < rhs.element.score
        }?.element
    }
}
