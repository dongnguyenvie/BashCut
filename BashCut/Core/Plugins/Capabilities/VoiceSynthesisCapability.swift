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

    public init(text: String, language: String, takeCount: Int, takeOffset: Int = 0, outputRoot: URL) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language
        self.takeCount = takeCount
        self.takeOffset = takeOffset
        self.outputRoot = outputRoot
    }

    public func validate() throws {
        guard !text.isEmpty else { throw PluginError.invalid("Voiceover text is required") }
        guard (1...8).contains(takeCount) else { throw PluginError.invalid("Voice take count must be 1...8") }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object([
            "language": .string(language), "outputDirectory": .string(outputDirectory?.path ?? ""),
            "takeCount": .integer(takeCount), "takeOffset": .integer(takeOffset), "text": .string(text),
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
                    durationSeconds: duration,
                    score: specification.score ?? Self.paceScore(text: text, duration: duration),
                    scoreSource: specification.score == nil ? "pace" : "provider"))
        }
        return takes
    }

    /// 1 when the take runs about 2.5 words per second, falling to 0 as it drifts from that.
    static func paceScore(text: String, duration: Double) -> Double {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let expected = max(1, Double(words) / 2.5)
        return max(0, min(1, 1 - abs(duration - expected) / expected))
    }
}
