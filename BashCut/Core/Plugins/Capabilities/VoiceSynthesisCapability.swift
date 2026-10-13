import AVFoundation
import BashCutPlugin
import BashCutProject
import Foundation

/// A saved clone sent with a `voice.synthesize` request as `reference` (#532): the reference clip's absolute path, the
/// clone's ID and name and its language.
public struct VoiceCloneReference: Sendable, Equatable {
    public let path: String
    public let voice: String
    public let name: String
    public let language: String

    public init(path: String, voice: String, name: String, language: String) {
        self.path = path
        self.voice = voice
        self.name = name
        self.language = language
    }

    var json: JSONValue {
        .object(["path": .string(path), "voice": .string(voice), "name": .string(name), "language": .string(language)])
    }
}

/// What to say the line with: a provider's preset (its `voice` option for this request) or a saved clone.
public enum VoiceChoice: Sendable, Equatable {
    case preset(String)
    case clone(VoiceCloneReference)

    /// The saved clone's language, nil for a preset.
    public var cloneLanguage: String? {
        if case .clone(let reference) = self { reference.language } else { nil }
    }
}

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
    /// A preset or saved clone chosen for this request; nil uses the plugin's own `voice` option.
    public let voice: VoiceChoice?

    public init(
        text: String, language: String, takeCount: Int, takeOffset: Int = 0, outputRoot: URL, cloneConsent: Bool = false,
        voice: VoiceChoice? = nil
    ) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language
        self.takeCount = takeCount
        self.takeOffset = takeOffset
        self.outputRoot = outputRoot
        self.cloneConsent = cloneConsent
        self.voice = voice
    }

    /// A preset is the plugin's `voice` option for this request only.
    public var optionOverrides: [String: JSONValue] {
        if case .preset(let id) = voice { return ["voice": .string(id)] }
        return [:]
    }

    public func validate() throws {
        guard !text.isEmpty else { throw PluginError.invalid("Voiceover text is required") }
        guard (1...8).contains(takeCount) else { throw PluginError.invalid("Voice take count must be 1...8") }
    }

    /// A saved clone adds `reference {path, voice, name, language}` and `cloneConsent: true` (its saved consent).
    public func params(outputDirectory: URL?) -> JSONValue {
        var fields: [String: JSONValue] = [
            "language": .string(language), "outputDirectory": .string(outputDirectory?.path ?? ""),
            "takeCount": .integer(takeCount), "takeOffset": .integer(takeOffset), "text": .string(text),
            "cloneConsent": .bool(cloneConsent),
        ]
        if case .clone(let reference) = voice {
            fields["reference"] = reference.json
            fields["cloneConsent"] = .bool(true)
        }
        return .object(fields)
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
