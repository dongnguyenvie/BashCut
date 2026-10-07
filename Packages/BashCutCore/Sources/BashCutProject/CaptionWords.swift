import Foundation

/// Word-by-word captions. A text item may carry `words`: `[{"text", "at", "dur"}]` in frames from the item's start
/// (from a transcription provider's word timings), and `wordStyle`, which shows the words as they are spoken:
///
/// - `highlight`: the word being spoken takes the highlight colour (`textStyle.highlight`, default yellow);
/// - `karaoke`: words already spoken take the highlight colour;
/// - `reveal`: words appear as they are spoken.
///
/// Words are the item's text split at white space, in reading order. When `words` is missing or no longer matches
/// the text (it was edited), timings are estimated from each word's length over the item.
public enum CaptionWords {
    public static let styles = ["highlight", "karaoke", "reveal"]
    public static let defaultHighlight = "#FFD400"
    public static let maximumWords = 2000

    /// One word with its time in seconds of the media it was heard in (transcription output), plus what the
    /// provider knows about it when it says: `confidence` (0–1), `speaker`, `event` (a non-speech sound such as
    /// laughter or music) and `noSpeechProb` (0–1, the chance its stretch holds no speech).
    public struct Timed: Codable, Sendable, Equatable {
        public let text: String
        public let start: Double
        public let end: Double
        public var confidence: Double?
        public var speaker: String?
        public var event: String?
        public var noSpeechProb: Double?

        public init(
            text: String, start: Double, end: Double, confidence: Double? = nil, speaker: String? = nil,
            event: String? = nil, noSpeechProb: Double? = nil
        ) {
            self.text = text
            self.start = start
            self.end = end
            self.confidence = confidence
            self.speaker = speaker
            self.event = event
            self.noSpeechProb = noSpeechProb
        }
    }

    /// Words of `text`: runs of non-white-space characters.
    public static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Reads a word-timings file: `[{"text"|"word", "start", "end"}]` in seconds, with the optional `confidence`
    /// (or `probability`), `speaker`, `event` and `noSpeechProb`; values out of range are left out.
    public static func decode(_ data: Data) throws -> [Timed] {
        guard data.count <= 8 * 1024 * 1024,
            let value = try? JSONDecoder().decode(JSONValue.self, from: data), case .array(let list) = value,
            list.count <= 500_000
        else { throw ProjectError.invalid("Word timings must be a JSON array of at most 500000 words") }
        return list.compactMap { entry in
            let fields = entry.object
            guard let text = (fields["text"] ?? fields["word"])?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty, let start = fields["start"]?.double, let end = fields["end"]?.double,
                start.isFinite, end.isFinite, start >= 0, end >= start
            else { return nil }
            let unit = { (value: JSONValue?) in value?.double.flatMap { (0...1).contains($0) ? $0 : nil } }
            let label = { (value: JSONValue?) in
                value?.string.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : String($0.prefix(64)) }
            }
            return Timed(
                text: text, start: start, end: end, confidence: unit(fields["confidence"] ?? fields["probability"]),
                speaker: label(fields["speaker"]), event: label(fields["event"]), noSpeechProb: unit(fields["noSpeechProb"]))
        }
    }
}

extension Item {
    /// The word display style, when the item shows its words as they are spoken.
    public var wordStyle: String? {
        fields["wordStyle"]?.string.flatMap { CaptionWords.styles.contains($0) ? $0 : nil }
    }

    /// Start and length (frames from the item's start) of each word of the text: from `words` when it matches the
    /// text word for word, otherwise spread over the item by word length.
    public var wordTimings: [(at: Int, duration: Int)] {
        let tokens = CaptionWords.tokens(text)
        guard !tokens.isEmpty else { return [] }
        if case .array(let list) = fields["words"], list.count == tokens.count {
            let timed = list.compactMap { entry -> (at: Int, duration: Int)? in
                guard let at = entry.object["at"]?.int, let duration = entry.object["dur"]?.int else { return nil }
                return (at, max(1, duration))
            }
            if timed.count == tokens.count { return timed }
        }
        let weights = tokens.map { Double($0.count) + 1 }
        let total = weights.reduce(0, +)
        var start = 0.0
        return weights.map { weight in
            let length = Double(duration) * weight / total
            defer { start += length }
            return (Int(start.rounded(.down)), max(1, Int(length.rounded())))
        }
    }

    /// Index of the word being spoken at `frame` (from the item's start): the last word that has started, or nil
    /// before the first.
    public func spokenWord(at frame: Int) -> Int? {
        wordTimings.lastIndex { $0.at <= frame }
    }

    /// `words` for this item from timed words heard at `seconds(frame)`: the words whose middle falls inside the
    /// item, in frames from its start. `frame` maps a word's media time to a timeline frame.
    public func attachingWords(_ words: [CaptionWords.Timed], frame: (Double) -> Int) -> Item {
        let inside = words.compactMap { word -> JSONValue? in
            let start = frame(word.start) - at, end = frame(word.end) - at
            let middle = (start + end) / 2
            guard (0..<duration).contains(middle) else { return nil }
            let from = max(0, start)
            return .object(["text": .string(word.text), "at": .integer(from),
                            "dur": .integer(max(1, min(duration, end) - from))])
        }
        guard !inside.isEmpty, inside.count <= CaptionWords.maximumWords else { return self }
        var item = self
        item["words"] = .array(inside)
        return item
    }

    func validateWords() throws {
        if let style = fields["wordStyle"], style != .null, style.string.map(CaptionWords.styles.contains) != true {
            throw ProjectError.invalid(
                "item.\(id).wordStyle: expected one of \(CaptionWords.styles.joined(separator: ", "))")
        }
        guard let value = fields["words"] else { return }
        guard case .array(let list) = value, list.count <= CaptionWords.maximumWords,
            list.allSatisfy({ entry in
                entry.object["text"]?.string != nil && entry.object["at"]?.int.map { $0 >= -2_000_000_000 } == true
                    && entry.object["dur"]?.int.map { $0 >= 1 } == true
            })
        else {
            throw ProjectError.invalid(
                "item.\(id).words: expected at most \(CaptionWords.maximumWords) {text, at, dur} entries")
        }
    }
}
