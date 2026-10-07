import BashCutPlugin
import BashCutProject
import Foundation

/// `audio.loudness`: integrated loudness, true peak and loudness range of a media file; with `bands`, also the energy
/// shares in the speech and presence bands (providers that do not know `bands` leave them out).
public struct LoudnessCapability: CapabilityAdapter {
    public static let capability = "audio.loudness"
    public let mediaURL: URL
    public let bands: Bool
    /// Also ask for loudness over time (#471); providers that do not know it leave it out.
    public let curve: Bool

    public init(mediaURL: URL, bands: Bool = false, curve: Bool = false) {
        self.mediaURL = mediaURL
        self.bands = bands
        self.curve = curve
    }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Loudness analysis source is unavailable")
        }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        var params: [String: JSONValue] = ["mediaPath": .string(mediaURL.path)]
        if bands { params["bands"] = .bool(true) }
        if curve { params["curve"] = .bool(true) }
        return .object(params)
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws
        -> GeneratedLoudnessMeasurement
    {
        GeneratedLoudnessMeasurement(measurement: try LoudnessMeasurement(result: result), provenance: context.provenance)
    }
}
