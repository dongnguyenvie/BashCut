import BashCutPlugin
import BashCutProject
import Foundation

/// `audio.loudness`: integrated loudness, true peak and loudness range of a media file.
public struct LoudnessCapability: CapabilityAdapter {
    public static let capability = "audio.loudness"
    public let mediaURL: URL

    public init(mediaURL: URL) { self.mediaURL = mediaURL }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Loudness analysis source is unavailable")
        }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object(["mediaPath": .string(mediaURL.path)])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws
        -> GeneratedLoudnessMeasurement
    {
        GeneratedLoudnessMeasurement(measurement: try LoudnessMeasurement(result: result), provenance: context.provenance)
    }
}
