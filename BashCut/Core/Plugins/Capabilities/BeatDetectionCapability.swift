import BashCutPlugin
import BashCutProject
import Foundation

/// `audio.beats`: tempo and beat times of a media file.
public struct BeatDetectionCapability: CapabilityAdapter {
    public static let capability = "audio.beats"
    public let mediaURL: URL

    public init(mediaURL: URL) { self.mediaURL = mediaURL }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Beat detection source is unavailable")
        }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object(["mediaPath": .string(mediaURL.path)])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> GeneratedBeatGrid {
        let values = result.object["beatsSeconds"]?.array ?? []
        let beats = values.compactMap(\.double)
        guard let bpm = result.object["bpm"]?.double, bpm.isFinite, (20...400).contains(bpm),
            !beats.isEmpty, beats.count == values.count, beats.count <= 100_000,
            beats.allSatisfy({ $0.isFinite && $0 >= 0 }),
            zip(beats, beats.dropFirst()).allSatisfy({ $0 < $1 })
        else { throw PluginError.invalid("Beat plugin returned invalid bpm or beatsSeconds") }
        var generated = GeneratedBeatGrid(bpm: bpm, beatSeconds: beats, provenance: context.provenance)
        generated.grid = Self.grid(result.object, beats: beats)
        return generated
    }

    /// The optional grid v2 fields that pass their checks; anything else is dropped.
    static func grid(_ values: [String: JSONValue], beats: [Double]) -> [String: JSONValue] {
        var grid: [String: JSONValue] = [:]
        let numbers = { (key: String) -> [Double]? in
            guard case .array(let list)? = values[key] else { return nil }
            let doubles = list.compactMap(\.double)
            return doubles.count == list.count && doubles.allSatisfy(\.isFinite) ? doubles : nil
        }
        if let strengths = numbers("strengths"), strengths.count == beats.count, strengths.allSatisfy({ (0...1).contains($0) }) {
            grid["strengths"] = .array(strengths.map(JSONValue.number))
        }
        if let downbeats = numbers("downbeats"), downbeats.allSatisfy({ beats.contains($0) }) {
            grid["downbeats"] = .array(downbeats.map(JSONValue.number))
        }
        if let bar = values["beatsPerBar"]?.int, (1...16).contains(bar) { grid["beatsPerBar"] = .integer(bar) }
        if let phases = numbers("phaseScores"), phases.count <= 16, phases.allSatisfy({ (0...1).contains($0) }) {
            grid["phaseScores"] = .array(phases.map(JSONValue.number))
        }
        if let confidence = values["confidence"]?.double, (0...1).contains(confidence) { grid["confidence"] = .number(confidence) }
        if case .object(let fit)? = values["fit"], fit.values.allSatisfy({ $0.double?.isFinite == true }) { grid["fit"] = .object(fit) }
        if case .array(let alternates)? = values["alternates"], alternates.count <= 8,
            alternates.allSatisfy({ $0.object["bpm"]?.double != nil })
        {
            grid["alternates"] = .array(alternates)
        }
        return grid
    }
}
