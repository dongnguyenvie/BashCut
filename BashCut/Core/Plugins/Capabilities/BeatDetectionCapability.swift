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
        return GeneratedBeatGrid(bpm: bpm, beatSeconds: beats, provenance: context.provenance)
    }
}
