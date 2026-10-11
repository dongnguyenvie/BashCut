import Foundation

/// One media's footage facts in a few lines (`media.digest`): what was measured, described and said, in time order,
/// so a plan can be written from one read instead of the analysis, description and transcript separately. Lines that
/// say nearly the same words again soon after are marked as possible retakes; which take to keep, and whether a line is
/// a cue to the camera, is the agent's call.
public struct MediaDigest: Sendable {
    public struct Phrase: Sendable, Equatable {
        public let start: Double
        public let end: Double
        public let text: String
        /// Start of a later phrase with nearly the same words (a possible retake of this one).
        public var againAt: Double?
    }

    public let media: String
    public let name: String
    public let seconds: Double
    public let size: String?
    /// Measured cut times (source seconds) when the picture was analysed.
    public let cuts: [Double]?
    public let shots: [MediaDescription.Shot]
    public let phrases: [Phrase]
    public let speechSeconds: Double?

    /// Phrases within this many seconds of each other can be retakes.
    public static let retakeWindow = 120.0
    /// Shared words over all words of both phrases (Jaccard) from which two phrases count as the same line, and the
    /// fewest shared words: languages of short words (Vietnamese) share many words between different lines.
    public static let retakeOverlap = 0.7
    public static let retakeSharedWords = 4

    public init(
        media: String, name: String, seconds: Double, size: String?, cuts: [Double]?, shots: [MediaDescription.Shot],
        phrases: [SubRip.Cue], speechSeconds: Double?
    ) {
        self.media = media
        self.name = name
        self.seconds = seconds
        self.size = size
        self.cuts = cuts
        self.shots = shots
        self.speechSeconds = speechSeconds
        self.phrases = Self.markRetakes(phrases.map { Phrase(start: $0.start, end: $0.end, text: $0.text, againAt: nil) })
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    static func markRetakes(_ phrases: [Phrase]) -> [Phrase] {
        let sets = phrases.map { Set(words($0.text)) }
        var marked = phrases
        for index in phrases.indices where sets[index].count >= 4 {
            for later in phrases.indices.dropFirst(index + 1) {
                guard phrases[later].start - phrases[index].start <= retakeWindow else { break }
                let shared = sets[index].intersection(sets[later]).count
                guard shared >= retakeSharedWords else { continue }
                if Double(shared) / Double(sets[index].union(sets[later]).count) >= retakeOverlap {
                    marked[index].againAt = phrases[later].start
                    break
                }
            }
        }
        return marked
    }

    static func clock(_ seconds: Double) -> String { String(format: "%.1f", seconds) }

    /// The digest limited to `from`…`to` source seconds.
    public func range(from: Double?, to: Double?) -> MediaDigest {
        let low = from ?? 0, high = to ?? .infinity
        var copy = self
        copy.rangeShots = shots.filter { $0.end > low && $0.start < high }
        copy.rangePhrases = phrases.filter { $0.end > low && $0.start < high }
        copy.rangeCuts = cuts?.filter { $0 >= low && $0 < high }
        return copy
    }

    private var rangeShots: [MediaDescription.Shot]?
    private var rangePhrases: [Phrase]?
    private var rangeCuts: [Double]?

    /// One header line, then described shots and phrases in time order:
    /// `shot 12.0-18.4 MS eye handheld | subjects | note`, `12.6 text [again 40.2]`, and the measured cuts of stretches
    /// no description covers.
    public var text: String {
        let shots = rangeShots ?? self.shots
        let phrases = rangePhrases ?? self.phrases
        var header = "media \(media) \"\(name)\" \(Self.clock(seconds))s"
        if let size { header += " \(size)" }
        if let speechSeconds, seconds > 0 { header += String(format: " speech %.0f%%", speechSeconds / seconds * 100) }
        header += " | \(phrases.count) phrases, \(shots.count) described shots"
        if let cuts = rangeCuts ?? cuts { header += ", \(cuts.count + 1) measured shots" }
        var rows: [(Double, Int, String)] = []
        for shot in shots {
            let look = [shot.size, shot.angle, shot.move].compactMap { $0 }.joined(separator: " ")
            let what = [shot.subjects.joined(separator: ", "), shot.note ?? ""].filter { !$0.isEmpty }
                .joined(separator: " | ")
            var line = "shot \(Self.clock(shot.start))-\(Self.clock(shot.end))"
            if !look.isEmpty { line += " \(look)" }
            if !what.isEmpty { line += " | \(what)" }
            if let best = shot.bestMoment { line += " | best \(Self.clock(best))" }
            rows.append((shot.start, 0, line))
        }
        for phrase in phrases {
            var line = "\(Self.clock(phrase.start)) \(phrase.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            if let again = phrase.againAt { line += " [again \(Self.clock(again))]" }
            rows.append((phrase.start, 1, line))
        }
        if let cuts = rangeCuts ?? cuts, !cuts.isEmpty {
            let undescribed = cuts.filter { cut in !shots.contains { $0.start <= cut && cut < $0.end } }
            if !undescribed.isEmpty {
                rows.append((-1, 0, "cuts " + undescribed.map(Self.clock).joined(separator: " ")))
            }
        }
        return ([header] + rows.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)).joined(separator: "\n")
    }

    public var json: JSONValue {
        let shots = rangeShots ?? self.shots
        let phrases = rangePhrases ?? self.phrases
        var fields: [String: JSONValue] = [
            "media": .string(media), "name": .string(name), "seconds": .number((seconds * 10).rounded() / 10),
            "shots": .array(shots.map { shot in
                var row: [String: JSONValue] = [
                    "from": .number(shot.start), "to": .number(shot.end),
                    "subjects": .array(shot.subjects.map(JSONValue.string)),
                ]
                for (key, value) in [("size", shot.size), ("angle", shot.angle), ("move", shot.move), ("note", shot.note)] {
                    if let value { row[key] = .string(value) }
                }
                if let best = shot.bestMoment { row["best"] = .number(best) }
                return .object(row)
            }),
            "phrases": .array(phrases.map { phrase in
                var row: [JSONValue] = [.number(phrase.start), .number(phrase.end), .string(phrase.text)]
                if let again = phrase.againAt { row.append(.number(again)) }
                return .array(row)
            }),
        ]
        if let size { fields["size"] = .string(size) }
        if let cuts = rangeCuts ?? cuts { fields["cuts"] = .array(cuts.map { .number(($0 * 100).rounded() / 100) }) }
        if let speechSeconds { fields["speechSeconds"] = .number((speechSeconds * 10).rounded() / 10) }
        return .object(fields)
    }
}
