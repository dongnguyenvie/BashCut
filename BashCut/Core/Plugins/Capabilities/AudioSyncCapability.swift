import BashCutPlugin
import BashCutProject
import Foundation

/// `audio.sync`: the time offset between two recordings of the same moment, from their sound.
/// Result: time in `otherPath` = time in `mediaPath` + `offsetSeconds`, with the match of each half of the overlap.
public struct AudioSyncCapability: CapabilityAdapter {
    public static let capability = "audio.sync"
    public let mediaURL: URL
    public let otherURL: URL

    public init(mediaURL: URL, otherURL: URL) {
        self.mediaURL = mediaURL
        self.otherURL = otherURL
    }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path), FileManager.default.fileExists(atPath: otherURL.path)
        else { throw PluginError.invalid("Sync analysis source is unavailable") }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object(["mediaPath": .string(mediaURL.path), "otherPath": .string(otherURL.path)])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> GeneratedAudioSync {
        let values = result.object
        func match(_ fields: [String: JSONValue]) -> GeneratedAudioSync.Match? {
            guard let offset = fields["offsetSeconds"]?.double, offset.isFinite, abs(offset) < 86_400,
                let correlation = fields["correlation"]?.double, correlation.isFinite, (-1.001...1.001).contains(correlation)
            else { return nil }
            return GeneratedAudioSync.Match(offsetSeconds: offset, correlation: min(1, max(-1, correlation)))
        }
        let halves = (values["halves"]?.array ?? []).map { match($0.object) }
        guard let overall = match(values), halves.count <= 2, halves.allSatisfy({ $0 != nil }) else {
            throw PluginError.invalid("Sync plugin returned an invalid offsetSeconds or correlation")
        }
        let start = values["overlapStartSeconds"]?.double, end = values["overlapEndSeconds"]?.double
        return GeneratedAudioSync(
            match: overall, halves: halves.compactMap { $0 },
            overlap: start.flatMap { start in end.flatMap { start.isFinite && $0.isFinite && $0 >= start ? start...$0 : nil } },
            provenance: context.provenance)
    }
}
