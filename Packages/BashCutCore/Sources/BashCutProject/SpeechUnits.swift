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

    public static func align(_ text: String, to spoken: [CaptionWords.Timed]) -> Result {
        let intended = SpeechUnits.tokens(text)
        let heard = spelledNumbers(spoken, intended: intended, language: NumberWords.language(of: text))
        let compared = { (token: String) in
            let word = SpeechUnits.normalized(token)
            return NumberWords.variants[word] ?? word
        }
        let left = intended.map(compared), right = heard.map { compared($0.text) }
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
    /// Heard numerals the script does not write as digits, as words over the numeral's time ("528" → năm trăm hai
    /// mươi tám), so a spelled-out number in the script matches what a recognizer wrote in digits. Heard units
    /// (also stuck to a number, "3,5km") the script does not write become the script's spoken form of them
    /// ("km" → cây số), sharing the unit's time.
    static func spelledNumbers(_ heard: [CaptionWords.Timed], intended: [String], language: String) -> [CaptionWords.Timed] {
        let script = intended.map(SpeechUnits.normalized)
        let written = Set(script)
        let numbers = joinedDecimals(heard).flatMap { word -> [CaptionWords.Timed] in
            let token = SpeechUnits.normalized(word.text)
            // A unit written onto the number ("3,5km") stays a word of its own after the spelled number.
            let digits = String(token.prefix { $0.isNumber || $0 == "." || $0 == "," || $0 == "%" })
            let unit = String(token.dropFirst(digits.count))
            guard !written.contains(token), let spelled = NumberWords.spelled(digits, language: language), !spelled.isEmpty
            else { return [word] }
            return split(word, into: spelled + (unit.isEmpty ? [] : [unit]))
        }
        return numbers.flatMap { word -> [CaptionWords.Timed] in
            let token = SpeechUnits.normalized(word.text)
            guard !written.contains(token), let spoken = UnitWords.spoken(token, language: language, in: script) else {
                return [word]
            }
            return split(word, into: spoken)
        }
    }

    /// A decimal a recognizer wrote in two words ("3" then ",3km", Whisper on Vietnamese "ba phẩy ba cây số") as one
    /// word over both times, so it spells with its "phẩy" / "point" instead of losing it.
    static func joinedDecimals(_ heard: [CaptionWords.Timed]) -> [CaptionWords.Timed] {
        var result: [CaptionWords.Timed] = []
        for word in heard {
            let text = word.text.trimmingCharacters(in: .whitespaces)
            if let last = result.last, !last.text.isEmpty, last.text.allSatisfy(\.isNumber),
                let mark = text.first, mark == "," || mark == ".", text.dropFirst().first?.isNumber == true
            {
                result[result.count - 1] = last.retimed(text: last.text + text, start: last.start, end: word.end)
            } else {
                result.append(word)
            }
        }
        return result
    }

    /// `word` as `texts`, its time shared evenly between them.
    static func split(_ word: CaptionWords.Timed, into texts: [String]) -> [CaptionWords.Timed] {
        guard texts.count > 1 else { return texts.map { word.retimed(text: $0, start: word.start, end: word.end) } }
        let step = max(0, word.end - word.start) / Double(texts.count)
        return texts.enumerated().map { index, text in
            word.retimed(text: text, start: word.start + step * Double(index), end: word.start + step * Double(index + 1))
        }
    }

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

/// Units as they are said (W6 follow-up of P0-C5): a recognizer writes "km" or "hectare" where the script spells
/// "cây số" or "héc ta". Each heard form maps to the spoken forms a script may use, per language; the first spoken
/// form found in the script wins, so a heard unit only changes when the script says it another way.
public enum UnitWords {
    /// Heard forms (normalized) → spoken forms, each as its words.
    public static let table: [String: [String: [[String]]]] = {
        let viKilometre: [[String]] = [["cây", "số"], ["ki", "lô", "mét"], ["ki-lô-mét"], ["kilômét"], ["km"]]
        let viHectare: [[String]] = [["héc", "ta"], ["héc-ta"], ["hecta"], ["ha"]]
        let viMetre: [[String]] = [["mét"]]
        let viKilogram: [[String]] = [["ki", "lô", "gam"], ["ki-lô-gam"], ["cân"], ["ký"], ["kí"], ["ki", "lô"], ["kg"]]
        let viMinute: [[String]] = [["phút"]]
        let viHour: [[String]] = [["giờ"], ["tiếng"]]
        let viDong: [[String]] = [["đồng"], ["nghìn", "đồng"]]
        let enKilometre: [[String]] = [["kilometres"], ["kilometers"], ["kilometre"], ["kilometer"], ["km"]]
        let enHectare: [[String]] = [["hectares"], ["hectare"], ["ha"]]
        let enKilogram: [[String]] = [["kilograms"], ["kilogram"], ["kilos"], ["kilo"], ["kg"]]
        let enMetre: [[String]] = [["metres"], ["meters"], ["metre"], ["meter"], ["m"]]
        let enMile: [[String]] = [["miles"], ["mile"], ["mi"]]
        return [
            "vi": [
                "km": viKilometre, "kilomet": viKilometre, "kilômét": viKilometre, "ki-lô-mét": viKilometre,
                "kilometer": viKilometre, "kilometre": viKilometre,
                "ha": viHectare, "hectare": viHectare, "hecta": viHectare, "héc-ta": viHectare,
                "m": viMetre, "met": viMetre,
                "kg": viKilogram, "kilogram": viKilogram, "kilôgam": viKilogram,
                "min": viMinute, "h": viHour, "đ": viDong, "vnđ": viDong, "vnd": viDong,
            ],
            "en": [
                "km": enKilometre, "kms": enKilometre, "ha": enHectare, "kg": enKilogram, "kgs": enKilogram,
                "m": enMetre, "mi": enMile,
                "kilometres": enKilometre, "kilometers": enKilometre, "kilometre": enKilometre, "kilometer": enKilometre,
            ],
        ]
    }()

    /// The script's spoken form of a heard unit token, or nil when the token is no unit, the script says no form
    /// of it, or says it the way it was heard.
    public static func spoken(_ token: String, language: String, in script: [String]) -> [String]? {
        guard let forms = table[language]?[token] else { return nil }
        for form in forms where form != [token] && contains(script, form) { return form }
        return nil
    }

    static func contains(_ script: [String], _ form: [String]) -> Bool {
        guard !form.isEmpty, script.count >= form.count else { return false }
        return (0...(script.count - form.count)).contains { Array(script[$0..<($0 + form.count)]) == form }
    }
}
