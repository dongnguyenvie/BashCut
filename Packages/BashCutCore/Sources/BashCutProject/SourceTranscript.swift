import Foundation

/// What was said in one source media, in that media's own seconds (P0-A2), independent of timeline captions:
/// the provider's phrases (its SubRip cues) and its words with whatever the provider knows about each one. It is
/// stored by file content, so `captions.generate` places captions from it without transcribing again, and
/// `transcript.words --heard` maps its words through the clips that play the media now.
public struct SourceTranscript: Codable, Sendable, Equatable {
    public static let version = 1

    public enum Format: String, CaseIterable, Sendable {
        case words, phrases, json, text
    }

    public let version: Int
    /// Content key of the file it was made from.
    public let key: String
    public let language: String
    /// `{plugin, provider, version}` of the `captions.transcribe` provider.
    public let provider: [String: JSONValue]
    public let transcribedAt: String
    public let phrases: [SubRip.Cue]
    public let words: [CaptionWords.Timed]

    public init(
        key: String, language: String, provider: [String: JSONValue], transcribedAt: String, phrases: [SubRip.Cue],
        words: [CaptionWords.Timed]
    ) {
        version = Self.version
        self.key = key
        self.language = language
        self.provider = provider
        self.transcribedAt = transcribedAt
        self.phrases = phrases.sorted { $0.start < $1.start }
        self.words = words.sorted { $0.start < $1.start }
    }

    /// The same transcript for another file with the same sound and times (a converted copy), under its key.
    public func keyed(_ key: String) -> SourceTranscript {
        SourceTranscript(
            key: key, language: language, provider: provider, transcribedAt: transcribedAt, phrases: phrases, words: words)
    }

    /// Which facts the provider gave: word times from the provider or none (phrases only), and whether any word
    /// carries a confidence, speaker, event or no-speech probability.
    public var precision: JSONValue {
        .object([
            "wordTimes": .string(words.isEmpty ? "none" : "provider"),
            "confidence": .bool(words.contains { $0.confidence != nil }),
            "speakers": .bool(words.contains { $0.speaker != nil }),
            "events": .bool(words.contains { $0.event != nil }),
            "noSpeechProb": .bool(words.contains { $0.noSpeechProb != nil }),
        ])
    }

    /// Seconds covered by phrases (overlaps counted once).
    public var speechSeconds: Double {
        var total = 0.0, reached = -Double.infinity
        for phrase in phrases {
            let start = max(phrase.start, reached)
            if phrase.end > start { total += phrase.end - start }
            reached = max(reached, phrase.end)
        }
        return total
    }

    public var overviewJSON: JSONValue {
        .object([
            "transcribed": .bool(true), "key": .string(key), "language": .string(language),
            "provider": .object(provider), "transcribedAt": .string(transcribedAt),
            "phrases": .integer(phrases.count), "words": .integer(words.count),
            "speechSeconds": .number(Self.rounded(speechSeconds)),
            "firstSpeech": phrases.first.map { .number(Self.rounded($0.start)) } ?? .null,
            "lastSpeech": phrases.map(\.end).max().map { .number(Self.rounded($0)) } ?? .null,
            "precision": precision,
        ])
    }

    /// The transcript between `from` and `to` source seconds (phrases and words that overlap it): `words`,
    /// `phrases`, both (`json`), or one line per phrase (`text`, a string).
    public func json(_ format: Format, from: Double = 0, to: Double? = nil) -> JSONValue {
        let inside = { (start: Double, end: Double) in end > from && to.map { start < $0 } ?? true }
        let phraseRows = phrases.enumerated().compactMap { index, phrase -> (Int, SubRip.Cue)? in
            inside(phrase.start, phrase.end) ? (index, phrase) : nil
        }
        if format == .text {
            return .string(phraseRows.map { index, phrase in
                let seconds = String(format: "%.2fs", phrase.end - phrase.start)
                return "#\(index + 1) \(TimelineTranscript.clock(phrase.start))–\(TimelineTranscript.clock(phrase.end)) "
                    + "\(seconds) | \(TimelineTranscript.oneLine(phrase.text))"
            }.joined(separator: "\n"))
        }
        var result: [String: JSONValue] = overviewJSON.object
        result["from"] = .number(from)
        result["to"] = to.map { .number($0) } ?? .null
        if format != .phrases {
            result["wordList"] = .array(words.enumerated().compactMap { index, word in
                guard inside(word.start, word.end) else { return nil }
                var row = Self.json(word)
                row["index"] = .integer(index)
                if index > 0 { row["gapBefore"] = .number(Self.rounded(word.start - words[index - 1].end)) }
                return .object(row)
            })
        }
        if format != .words {
            result["phraseList"] = .array(phraseRows.map { index, phrase in
                let heard = words(in: phrase)
                let scores = heard.compactMap(\.confidence)
                var row: [String: JSONValue] = [
                    "index": .integer(index + 1), "start": .number(Self.rounded(phrase.start)),
                    "end": .number(Self.rounded(phrase.end)), "seconds": .number(Self.rounded(phrase.end - phrase.start)),
                    "text": .string(phrase.text), "words": .integer(heard.count),
                    "confidence": scores.isEmpty ? .null : .number(Self.rounded(scores.reduce(0, +) / Double(scores.count))),
                ]
                if index > 0 { row["gapBefore"] = .number(Self.rounded(phrase.start - phrases[index - 1].end)) }
                return .object(row)
            })
        }
        return .object(result)
    }

    /// Words whose middle falls inside `phrase`.
    public func words(in phrase: SubRip.Cue) -> [CaptionWords.Timed] {
        let first = words.partitioningIndex { $0.end > phrase.start }
        return words[first...].prefix { $0.start < phrase.end }.filter {
            let middle = ($0.start + $0.end) / 2
            return middle >= phrase.start && middle <= phrase.end
        }
    }

    /// One word as JSON: text, start, end and the provider facts it has.
    static func json(_ word: CaptionWords.Timed) -> [String: JSONValue] {
        var row: [String: JSONValue] = [
            "text": .string(word.text), "start": .number(rounded(word.start)), "end": .number(rounded(word.end)),
        ]
        if let confidence = word.confidence { row["confidence"] = .number(rounded(confidence)) }
        if let speaker = word.speaker { row["speaker"] = .string(speaker) }
        if let event = word.event { row["event"] = .string(event) }
        if let noSpeechProb = word.noSpeechProb { row["noSpeechProb"] = .number(rounded(noSpeechProb)) }
        return row
    }

    static func rounded(_ value: Double) -> Double { TimelineTranscript.rounded(value) }
}
