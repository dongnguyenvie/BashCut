import BashCutPlugin
import BashCutProject
import Foundation

/// Which pictures of a media file a vision provider looks at: one every `step` source seconds over from…to.
public struct VisionSampling: Sendable, Equatable {
    public static let maximumSamples = 3_600
    public let mediaURL: URL
    public let step: Double
    public let fromSeconds: Double?
    public let toSeconds: Double?

    public init(mediaURL: URL, step: Double = 1, fromSeconds: Double? = nil, toSeconds: Double? = nil) {
        self.mediaURL = mediaURL
        self.step = step
        self.fromSeconds = fromSeconds
        self.toSeconds = toSeconds
    }

    func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Vision source is unavailable")
        }
        guard step.isFinite, step > 0 else { throw PluginError.invalid("step must be over 0 seconds") }
        if let fromSeconds, let toSeconds, toSeconds < fromSeconds { throw PluginError.invalid("to must not be before from") }
    }

    var params: [String: JSONValue] {
        var values: [String: JSONValue] = ["mediaPath": .string(mediaURL.path), "step": .number(step)]
        if let fromSeconds { values["fromSeconds"] = .number(fromSeconds) }
        if let toSeconds { values["toSeconds"] = .number(toSeconds) }
        return values
    }

    /// The provider's `frames` with each list checked: every entry has a `box` of four shares (0…1) and a finite
    /// `confidence` (and, for `text`, a `string`). Other fields a provider adds are kept.
    static func frames(_ result: JSONValue, lists: [String]) throws -> [JSONValue] {
        guard case .array(let frames)? = result.object["frames"], frames.count <= maximumSamples,
            frames.allSatisfy({ frame in
                guard let seconds = frame.object["seconds"]?.double, seconds.isFinite, seconds >= 0 else { return false }
                return lists.allSatisfy { key in
                    guard case .array(let entries)? = frame.object[key], entries.count <= 1_000 else { return false }
                    return entries.allSatisfy { entry in
                        let box = entry.object["box"]?.array.compactMap(\.double) ?? []
                        return box.count == 4 && box.allSatisfy { (0...1).contains($0) }
                            && entry.object["confidence"]?.double?.isFinite == true
                            && (key != "text" || entry.object["string"]?.string != nil)
                    }
                }
            })
        else { throw PluginError.invalid("Vision plugin returned invalid frames") }
        return frames
    }
}

/// `vision.faces` (P2-H6): face and person boxes with confidence in each sampled picture. No labels or verdicts.
public struct FacesCapability: CapabilityAdapter {
    public static let capability = "vision.faces"
    public let sampling: VisionSampling

    public init(_ sampling: VisionSampling) { self.sampling = sampling }

    public func validate() throws { try sampling.validate() }

    public func params(outputDirectory: URL?) -> JSONValue { .object(sampling.params) }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> GeneratedVision {
        GeneratedVision(
            step: sampling.step, frames: try VisionSampling.frames(result, lists: ["faces", "people"]),
            provenance: context.provenance)
    }
}

/// `vision.text` (P2-H7): lines of on-screen text with their boxes and confidence in each sampled picture.
public struct TextRecognitionCapability: CapabilityAdapter {
    public static let capability = "vision.text"
    public let sampling: VisionSampling
    /// BCP 47 languages to try in order; empty lets the provider pick.
    public let languages: [String]

    public init(_ sampling: VisionSampling, languages: [String] = []) {
        self.sampling = sampling
        self.languages = languages
    }

    public func validate() throws { try sampling.validate() }

    public func params(outputDirectory: URL?) -> JSONValue {
        var values = sampling.params
        if !languages.isEmpty { values["languages"] = .array(languages.map(JSONValue.string)) }
        return .object(values)
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> GeneratedVision {
        GeneratedVision(
            step: sampling.step, frames: try VisionSampling.frames(result, lists: ["text"]), provenance: context.provenance)
    }
}
