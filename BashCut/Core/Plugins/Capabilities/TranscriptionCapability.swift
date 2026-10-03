import BashCutPlugin
import BashCutProject
import Foundation

/// `captions.transcribe`: the plugin writes an SRT file for a media file into the request folder, and optionally a
/// JSON file of word timings (`wordsPath`: `[{"text", "start", "end"}]` in seconds) for word-by-word captions.
public struct TranscriptionCapability: CapabilityAdapter {
    public static let capability = "captions.transcribe"
    public let mediaURL: URL
    public let language: String
    public let outputRoot: URL?

    public init(mediaURL: URL, language: String, outputRoot: URL) {
        self.mediaURL = mediaURL
        self.language = language
        self.outputRoot = outputRoot
    }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Transcription source is unavailable")
        }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object([
            "language": .string(language), "mediaPath": .string(mediaURL.path),
            "outputDirectory": .string(outputDirectory?.path ?? ""),
        ])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> GeneratedPluginCaptions {
        guard let path = result.object["srtPath"]?.string, !path.isEmpty else {
            throw PluginError.invalid("Transcription plugin did not return srtPath")
        }
        let srt = try context.confinedOutput(path, label: "Transcription plugin")
        let handle = try FileHandle(forReadingFrom: srt)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: SubRip.maximumBytes + 1) ?? Data()
        guard data.count <= SubRip.maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw PluginError.invalid("Transcription output must be UTF-8 SRT no larger than 4 MiB")
        }
        var words: [CaptionWords.Timed] = []
        if let path = result.object["wordsPath"]?.string, !path.isEmpty {
            let url = try context.confinedOutput(path, label: "Transcription plugin")
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            words = try CaptionWords.decode(handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data())
        }
        return GeneratedPluginCaptions(text: text, provenance: context.provenance, words: words)
    }
}
