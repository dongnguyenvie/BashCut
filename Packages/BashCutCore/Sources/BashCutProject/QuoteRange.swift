import Foundation

/// A source range from what was said (P1-D7, `media.resolve-range`): a quote, word indices or rough times in, word
/// edges out, with how far each edge moved, whether it falls inside a word or a sentence (a transcript phrase) and the
/// nearest word and sentence boundaries on each side. It finds; it does not rank.
public enum QuoteRange {
    /// Every place the quote's words appear in order with the most of them matching, earliest first.
    public static func find(_ quote: String, in words: [CaptionWords.Timed]) -> [(first: Int, last: Int, matched: Int)] {
        let wanted = SpeechUnits.tokens(quote).map(SpeechUnits.normalized)
        let heard = words.map { SpeechUnits.normalized($0.text) }
        guard !wanted.isEmpty, heard.count >= wanted.count else { return [] }
        var best = 0
        var found: [(first: Int, last: Int, matched: Int)] = []
        for start in 0...(heard.count - wanted.count) {
            let matched = zip(wanted, heard[start..<(start + wanted.count)]).filter { $0 == $1 }.count
            guard matched > 0, matched >= best else { continue }
            if matched > best { found = [] }
            best = matched
            found.append((start, start + wanted.count - 1, matched))
        }
        return found
    }

    /// One edge at `time` (seconds): inside a word or phrase, and the boundaries around it.
    static func edge(_ time: Double, words: [CaptionWords.Timed], phrases: [SubRip.Cue], fps: Double, isStart: Bool) -> JSONValue {
        let tolerance = 1 / fps
        let insideWord = words.contains { $0.start + tolerance < time && time < $0.end - tolerance }
        let insidePhrase = phrases.contains { $0.start + tolerance < time && time < $0.end - tolerance }
        let wordEdges = words.map { isStart ? $0.start : $0.end }
        let sentenceEdges = phrases.map { isStart ? $0.start : $0.end }
        let round = { (value: Double?) in value.map { JSONValue.number(($0 * 1_000).rounded() / 1_000) } ?? .null }
        return .object([
            "seconds": round(time), "midWord": .bool(insideWord), "midSentence": .bool(insidePhrase),
            "wordEdgeBefore": round(wordEdges.filter { $0 <= time + tolerance }.max()),
            "wordEdgeAfter": round(wordEdges.filter { $0 >= time - tolerance }.min()),
            "sentenceEdgeBefore": round(sentenceEdges.filter { $0 <= time + tolerance }.max()),
            "sentenceEdgeAfter": round(sentenceEdges.filter { $0 >= time - tolerance }.min()),
        ])
    }

    /// The range for word indices `first...last`, or for rough times snapped outwards to the words they cut into.
    public static func json(
        _ transcript: SourceTranscript, media: Media, first: Int? = nil, last: Int? = nil, from: Double? = nil,
        to: Double? = nil, matches: Int = 1
    ) throws -> JSONValue {
        let words = transcript.words.filter { $0.event == nil }
        let fps = media.fps.value > 0 ? media.fps.value : 30
        var start: Double, end: Double, requested: (Double, Double)?
        if let first, let last {
            guard words.indices.contains(first), words.indices.contains(last), first <= last else {
                throw ProjectError.invalid("Word indices must be within 0…\(words.count - 1), first ≤ last")
            }
            (start, end) = (words[first].start, words[last].end)
        } else if let from, let to, from < to {
            requested = (from, to)
            start = words.first { $0.start < from && from < $0.end }?.start ?? from
            end = words.first { $0.start < to && to < $0.end }?.end ?? to
        } else {
            throw ProjectError.invalid("Give a quote, word indices or from < to")
        }
        let inside = words.indices.filter { words[$0].end > start && words[$0].start < end }
        var row: [String: JSONValue] = [
            "media": .string(media.id), "from": .number((start * 1_000).rounded() / 1_000),
            "to": .number((end * 1_000).rounded() / 1_000),
            "inFrame": .integer(Int((start * fps).rounded(.down))), "outFrame": .integer(Int((end * fps).rounded(.up))),
            "text": .string(inside.map { words[$0].text }.joined(separator: " ")),
            "words": inside.first.map { .object(["first": .integer($0), "last": .integer(inside.last ?? $0)]) } ?? .null,
            "in": edge(start, words: words, phrases: transcript.phrases, fps: fps, isStart: true),
            "out": edge(end, words: words, phrases: transcript.phrases, fps: fps, isStart: false),
            "matches": .integer(matches),
        ]
        if let requested {
            row["snap"] = .object([
                "inDelta": .number(((start - requested.0) * 1_000).rounded() / 1_000),
                "outDelta": .number(((end - requested.1) * 1_000).rounded() / 1_000),
            ])
        }
        return .object(row)
    }
}
