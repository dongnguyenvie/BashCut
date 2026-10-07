import AVFoundation
import BashCutPlugin
import BashCutProject
import Foundation

/// `voice.synthesize`: one batch of voice takes for a line of text, written as audio files into the
/// request folder. `CapabilityService.synthesizeVoiceTakes` repeats it until enough takes exist.
public struct VoiceSynthesisCapability: CapabilityAdapter {
    public static let capability = "voice.synthesize"
    public let text: String
    public let language: String
    public let takeCount: Int
    public let takeOffset: Int
    public let outputRoot: URL?
    /// The person asking agreed to clone a voice (P0-C7); providers that clone refuse without it.
    public let cloneConsent: Bool

    public init(
        text: String, language: String, takeCount: Int, takeOffset: Int = 0, outputRoot: URL, cloneConsent: Bool = false
    ) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language
        self.takeCount = takeCount
        self.takeOffset = takeOffset
        self.outputRoot = outputRoot
        self.cloneConsent = cloneConsent
    }

    public func validate() throws {
        guard !text.isEmpty else { throw PluginError.invalid("Voiceover text is required") }
        guard (1...8).contains(takeCount) else { throw PluginError.invalid("Voice take count must be 1...8") }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object([
            "language": .string(language), "outputDirectory": .string(outputDirectory?.path ?? ""),
            "takeCount": .integer(takeCount), "takeOffset": .integer(takeOffset), "text": .string(text),
            "cloneConsent": .bool(cloneConsent),
        ])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> [GeneratedVoiceTake] {
        var takes: [GeneratedVoiceTake] = []
        for specification in try VoiceSynthesisResultParser.parse(result) {
            let audio = try context.confinedOutput(specification.audioPath, label: "Voice plugin")
            let asset = AVURLAsset(url: audio)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0, try await !asset.loadTracks(withMediaType: .audio).isEmpty
            else { throw PluginError.invalid("Voice plugin output is not a valid audio file") }
            takes.append(
                GeneratedVoiceTake(
                    asset: GeneratedPluginAsset(url: audio, provenance: context.provenance),
                    durationSeconds: duration, score: specification.score))
        }
        return takes
    }
}
