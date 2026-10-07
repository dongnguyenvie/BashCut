import Foundation

/// How speech is counted for a language (P0-C2): Vietnamese is written one syllable per word, so it counts
/// syllables; Chinese, Japanese and Korean count characters; other languages count words. Rates are units per second;
/// core holds no "normal" rate.
public enum SpeechUnits {
    public enum Unit: String, Sendable, CaseIterable {
        case syllables, words, characters
    }

    public static func unit(for language: String) -> Unit {
        switch language.lowercased().prefix(2) {
        case "vi": .syllables
        case "zh", "ja", "ko": .characters
        default: .words
        }
    }

    /// Word tokens: whitespace-separated runs that hold a letter or digit, with punctuation trimmed.
    public static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
    }

    public static func count(_ text: String, unit: Unit) -> Int {
        switch unit {
        case .syllables, .words: tokens(text).count
        case .characters: text.filter { $0.isLetter || $0.isNumber }.count
        }
    }

    /// A token as compared between a script and what was heard: lowercased, without punctuation.
    public static func normalized(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
    }
}

/// The words of an intended text matched to timed words that were heard (P0-C5 `voice check`, P0-C9 alignment), by
/// edit distance over normalized tokens (a substitution costs as much as a missing plus an extra word, so the most
/// words match): each intended word is matched, substituted (heard as another word) or missing,
/// and heard words left over are extra. Times come from the heard word; a missing word gets the time between its
/// neighbours.
public enum TextAlignment {
    public struct Word: Sendable, Equatable {
        public var text: String
        public var heard: String?
        public var start: Double
        public var end: Double
        public var kind: String
    }

    public struct Result: Sendable, Equatable {
        public var words: [Word]
        /// Heard words no intended word matched.
        public var extra: [CaptionWords.Timed]
        /// Matched intended words over the longer of the two word counts.
        public var similarity: Double
    }

    public static func align(_ text: String, to heard: [CaptionWords.Timed]) -> Result {
        let intended = SpeechUnits.tokens(text)
        let left = intended.map(SpeechUnits.normalized), right = heard.map { SpeechUnits.normalized($0.text) }
        let rows = left.count, columns = right.count
        var cost = [[Int]](repeating: [Int](repeating: 0, count: columns + 1), count: rows + 1)
        for row in 0...rows { cost[row][0] = row }
        for column in 0...columns { cost[0][column] = column }
        if rows > 0, columns > 0 {
            for row in 1...rows {
                for column in 1...columns {
                    let same = left[row - 1] == right[column - 1]
                    cost[row][column] = min(
                        cost[row - 1][column - 1] + (same ? 0 : 2), cost[row - 1][column] + 1, cost[row][column - 1] + 1)
                }
            }
        }
        // Walk back: diagonal for a match or substitution, up for a missing word, left for an extra one.
        var row = rows, column = columns
        var words: [Word?] = Array(repeating: nil, count: rows)
        var extra: [CaptionWords.Timed] = []
        while row > 0 || column > 0 {
            if row > 0, column > 0,
                cost[row][column] == cost[row - 1][column - 1] + (left[row - 1] == right[column - 1] ? 0 : 2)
            {
                let word = heard[column - 1]
                words[row - 1] = Word(
                    text: intended[row - 1], heard: word.text, start: word.start, end: word.end,
                    kind: left[row - 1] == right[column - 1] ? "match" : "substituted")
                row -= 1
                column -= 1
            } else if row > 0, cost[row][column] == cost[row - 1][column] + 1 {
                row -= 1
            } else {
                extra.insert(heard[column - 1], at: 0)
                column -= 1
            }
        }
        var result: [Word] = []
        for (index, word) in words.enumerated() {
            if let word {
                result.append(word)
                continue
            }
            let before = result.last?.end ?? heard.first?.start ?? 0
            let after = words[(index + 1)...].compactMap { $0 }.first?.start ?? heard.last?.end ?? before
            result.append(Word(text: intended[index], heard: nil, start: before, end: max(before, after), kind: "missing"))
        }
        let matched = result.filter { $0.kind == "match" }.count
        return Result(words: result, extra: extra, similarity: Double(matched) / Double(max(1, max(rows, columns))))
    }
}

extension TextAlignment {
    /// Captions whose text is the script and whose times come from the speech (P0-C9): each non-empty line of
    /// `script` becomes a cue from its first word's start to its last word's end, with the script's own words timed
    /// on it. Lines without a single matched word keep the time between their neighbours.
    public static func cues(script: String, heard: [CaptionWords.Timed])
        -> (cues: [SubRip.Cue], words: [CaptionWords.Timed], alignment: Result)
    {
        let lines = script.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !SpeechUnits.tokens($0).isEmpty }
        let alignment = align(lines.joined(separator: " "), to: heard)
        var cues: [SubRip.Cue] = [], words: [CaptionWords.Timed] = []
        var index = 0
        for line in lines {
            let count = SpeechUnits.tokens(line).count
            let part = alignment.words[index..<min(alignment.words.count, index + count)]
            index += count
            guard let first = part.first, let last = part.last else { continue }
            let start = first.start, end = max(last.end, start + 0.01)
            cues.append(SubRip.Cue(start: start, end: end, text: line))
            words += part.map { CaptionWords.Timed(text: $0.text, start: $0.start, end: max($0.end, $0.start + 0.01)) }
        }
        return (cues, words, alignment)
    }

    /// Words that were not heard as written: substituted or missing, with their times.
    public static func unmatchedJSON(_ result: Result) -> JSONValue {
        .array(result.words.filter { $0.kind != "match" }.map { word in
            .object([
                "text": .string(word.text), "heard": word.heard.map(JSONValue.string) ?? .null, "kind": .string(word.kind),
                "start": .number((word.start * 1_000).rounded() / 1_000), "end": .number((word.end * 1_000).rounded() / 1_000),
            ])
        })
    }
}
