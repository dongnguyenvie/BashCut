import BashCutPlugin
import BashCutProject
import Foundation

/// `captions.align` (P0-C9): force-align known text to a media's speech. Result: `words` [{text, start, end}] in
/// media seconds, one per word of the text in order, an alignment `score` 0–1 and `unmatched` words.
public struct CaptionsAlignCapability: CapabilityAdapter {
    public static let capability = "captions.align"
    public let mediaURL: URL
    public let text: String
    public let language: String

    public init(mediaURL: URL, text: String, language: String) {
        self.mediaURL = mediaURL
        self.text = text
        self.language = language
    }

    public func validate() throws {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw PluginError.invalid("Alignment source is unavailable")
        }
        guard !SpeechUnits.tokens(text).isEmpty else { throw PluginError.invalid("The text has no words") }
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        .object(["mediaPath": .string(mediaURL.path), "text": .string(text), "language": .string(language)])
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> [CaptionWords.Timed] {
        let words = (result.object["words"]?.array ?? []).compactMap { word -> CaptionWords.Timed? in
            guard let text = word.object["text"]?.string, let start = word.object["start"]?.double,
                let end = word.object["end"]?.double, start.isFinite, end.isFinite, start >= 0, end >= start
            else { return nil }
            return CaptionWords.Timed(text: text, start: start, end: end)
        }
        guard !words.isEmpty, words.count == result.object["words"]?.array.count else {
            throw PluginError.invalid("Alignment plugin returned invalid words")
        }
        return words
    }
}
