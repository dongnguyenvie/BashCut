import BashCutPlugin
import BashCutProject
import Foundation

/// `audio.loudness`: integrated loudness, true peak and loudness range of a media file; with `bands`, also the energy
/// shares in the speech and presence bands (providers that do not know `bands` leave them out).
public struct LoudnessCapability: CapabilityAdapter {
    public static let capability = "audio.loudness"
    public let mediaURL: URL
    public let bands: Bool

    public init(mediaURL: URL, bands: Bool = false) {
        self.mediaURL = mediaURL
        self.bands = bands
    }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Loudness analysis source is unavailable")
        }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object(bands ? ["mediaPath": .string(mediaURL.path), "bands": .bool(true)] : ["mediaPath": .string(mediaURL.path)])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws
        -> GeneratedLoudnessMeasurement
    {
        GeneratedLoudnessMeasurement(measurement: try LoudnessMeasurement(result: result), provenance: context.provenance)
    }
}
