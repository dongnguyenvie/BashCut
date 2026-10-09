import Foundation

/// The edit as one list (`plan.cut`, `plan.check`, `plan.apply`): clips on Main in order (by quote, word indices or
/// source seconds), pictures over a clip's sound, titles anchored to a clip, one music bed. The agent writes it once,
/// checks it without touching the timeline, then builds it as one undoable edit; changing the edit is changing the
/// list and applying it again. What it builds carries `planCut` (the entry's ID), so a later apply replaces exactly
/// that and nothing else.
public enum PlanCut {
    /// The field marking items `plan.apply` built.
    public static let tag = "planCut"
    /// The section a built clip opened or belongs to, so the next apply removes its marker too.
    static let sectionTag = "planSection"

    public struct Clip: Sendable {
        public var id: String
        public var media: String
        public var quote: String?
        public var words: (first: Int, last: Int)?
        public var from: Double?
        public var to: Double?
        public var seconds: Double?
        public var section: String?
        public var speed: Double
        public var volumeDb: Double?
        /// The speech coverage role its items are tagged with (speech, broll, underVO); speech by default for a
        /// clip picked by quote or words.
        public var role: String?
        /// Pictures shown over the clip's sound, in order (B-roll); the last one fills what is left.
        public var cover: [Cover] = []
    }

    /// A picture laid over a clip's sound: source seconds `from` of `media`, for `seconds` (the last: the rest).
    public struct Cover: Sendable {
        public var media: String
        public var from: Double
        public var seconds: Double?
    }

    public struct Title: Sendable {
        public var id: String
        public var text: String
        public var clip: String?
        public var offset: Double
        public var at: Double?
        public var seconds: Double
        /// A renderer preset (`TextPreset.all`) or a library text preset's ID.
        public var preset: String?
        /// Item properties other than the text style.
        public var style: [String: JSONValue]
        /// Text style fields (font, size, fill, stroke…), over the preset's.
        public var textStyle: [String: JSONValue] = [:]
    }

    /// The `textStyle` fields a title's `style` may give directly.
    public static let textStyleKeys = ItemProperty.all.filter { $0.group == "textStyle" }.map(\.key)
        + ["background", "shadow", "emphasis", "lineFills", "accentBars"]

    public struct Music: Sendable {
        public var media: String
        public var from: Double
        public var volumeDb: Double?
        /// The music layer's level under speech (its ducking), in dB.
        public var duckDb: Double?
    }

    /// Captions from what the clips say (their media's stored transcripts), in a preset and style.
    public struct Captions: Sendable {
        public var wordStyle: String?
        public var preset: String?
        public var style: [String: JSONValue] = [:]
        public var textStyle: [String: JSONValue] = [:]
    }

    public struct Spec: Sendable {
        public var clips: [Clip]
        public var titles: [Title]
        public var music: Music?
        public var captions: Captions?
    }

    static let roles = ["speech", "broll", "underVO"]

    /// A clip's source range once resolved, with the facts behind it.
    public struct Resolved: Sendable {
        public var clip: Clip
        public var from: Double
        public var to: Double
        public var facts: [String: JSONValue]
    }

    /// A problem with the list itself (unknown media, a quote not heard, overlapping reuse); `error` blocks apply.
    public struct Problem: Sendable {
        public var id: String
        public var severity: String
        public var entry: String?
        public var detail: String
        public var facts: [String: JSONValue] = [:]

        public init(id: String, severity: String, entry: String?, detail: String, facts: [String: JSONValue] = [:]) {
            self.id = id
            self.severity = severity
            self.entry = entry
            self.detail = detail
            self.facts = facts
        }

        public var json: JSONValue {
            var row: [String: JSONValue] = ["id": .string(id), "severity": .string(severity), "detail": .string(detail)]
            if let entry { row["entry"] = .string(entry) }
            if !facts.isEmpty { row["facts"] = .object(facts) }
            return .object(row)
        }
    }

    // MARK: Decoding

    public static func decode(_ value: JSONValue) throws -> Spec {
        guard case .object(let root) = value else { throw ProjectError.invalid("plan.cut must be an object {clips, titles, music}") }
        guard case .array(let clipValues)? = root["clips"], !clipValues.isEmpty else {
            throw ProjectError.invalid("plan.cut.clips must list at least one clip")
        }
        var ids = IDs()
        let clips = try clipValues.enumerated().map { index, value in
            try decodeClip(value.object, id: ids.take(value.object["id"]?.string, "c", index))
        }
        let titles = try (root["titles"]?.array ?? []).enumerated().map { index, value in
            try decodeTitle(value.object, id: ids.take(value.object["id"]?.string, "t", index), clips: clips)
        }
        var music: Music?
        if case .object(let row)? = root["music"] {
            guard let media = row["media"]?.string else { throw ProjectError.invalid("music: give media") }
            let duck = row["duckDb"]?.double
            if let duck, !(-60...0).contains(duck) { throw ProjectError.invalid("music.duckDb: -60…0") }
            music = Music(media: media, from: max(0, row["from"]?.double ?? 0), volumeDb: row["volumeDb"]?.double, duckDb: duck)
        }
        return Spec(clips: clips, titles: titles, music: music, captions: try decodeCaptions(root["captions"]))
    }

    /// `captions: {from: "speech", wordStyle, preset, style}`; null or false: none.
    static func decodeCaptions(_ value: JSONValue?) throws -> Captions? {
        guard let value, value != .null, value != .bool(false) else { return nil }
        let row = value.object
        guard (row["from"]?.string ?? "speech") == "speech" else {
            throw ProjectError.invalid("captions.from: speech (captions from what the clips say)")
        }
        let wordStyle = row["wordStyle"]?.string
        if let wordStyle, !CaptionWords.styles.contains(wordStyle) {
            throw ProjectError.invalid("captions.wordStyle: \(CaptionWords.styles.joined(separator: ", "))")
        }
        let (style, textStyle) = splitStyle(row["style"]?.object ?? [:])
        return Captions(wordStyle: wordStyle, preset: row["preset"]?.string, style: style, textStyle: textStyle)
    }

    /// Text style fields (straight or nested as `textStyle`) apart from item properties.
    static func splitStyle(_ style: [String: JSONValue]) -> (item: [String: JSONValue], text: [String: JSONValue]) {
        let keys = Set(textStyleKeys)
        var text = style["textStyle"]?.object ?? [:]
        for (key, value) in style where keys.contains(key) { text[key] = value }
        return (style.filter { !keys.contains($0.key) && $0.key != "textStyle" }, text)
    }

    /// Entry IDs: given or numbered, unique across clips and titles.
    struct IDs {
        var seen = Set<String>()

        mutating func take(_ raw: String?, _ prefix: String, _ index: Int) throws -> String {
            let id = raw ?? "\(prefix)\(index + 1)"
            guard !id.isEmpty, id.count <= 64, id.allSatisfy({ $0.isLetter || $0.isNumber || "-_.".contains($0) }) else {
                throw ProjectError.invalid("\(prefix) ID \(id): use 1–64 letters, digits, '-', '_' or '.'")
            }
            guard seen.insert(id).inserted else { throw ProjectError.invalid("Duplicate plan.cut ID \(id)") }
            return id
        }
    }

    static func decodeClip(_ row: [String: JSONValue], id: String) throws -> Clip {
        guard let media = row["media"]?.string, !media.isEmpty else { throw ProjectError.invalid("Clip \(id): give media") }
        let quote = row["quote"]?.string.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let words = try row["words"]?.string.map { span in
            let parts = span.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { throw ProjectError.invalid("Clip \(id): words is FIRST-LAST, such as 12-30") }
            return (first: parts[0], last: parts[1])
        }
        let from = row["from"]?.double, to = row["to"]?.double, seconds = row["seconds"]?.double
        guard [quote != nil, words != nil, from != nil || to != nil].filter({ $0 }).count <= 1 else {
            throw ProjectError.invalid("Clip \(id): give one of quote, words or from/to")
        }
        if from != nil || to != nil {
            guard let from, let to, from >= 0, to > from else { throw ProjectError.invalid("Clip \(id): from < to, in seconds") }
        }
        if let seconds, seconds <= 0 { throw ProjectError.invalid("Clip \(id): seconds must be above 0") }
        let speed = row["speed"]?.double ?? 1
        guard Project.speedRange.contains(speed) else { throw ProjectError.invalid("Clip \(id): speed 0.1…16") }
        let cover = try (row["cover"]?.array ?? []).map { try decodeCover($0.object, clip: id) }
        let role = row["role"]?.string
        if let role, !roles.contains(role) { throw ProjectError.invalid("Clip \(id): role is \(roles.joined(separator: ", "))") }
        guard cover.isEmpty || speed == 1 else { throw ProjectError.invalid("Clip \(id): a covered clip plays at 1×") }
        return Clip(
            id: id, media: media, quote: quote, words: words, from: from, to: to, seconds: seconds,
            section: row["section"]?.string, speed: speed, volumeDb: row["volumeDb"]?.double,
            role: role ?? (quote != nil || words != nil ? "speech" : nil), cover: cover)
    }

    static func decodeCover(_ shot: [String: JSONValue], clip id: String) throws -> Cover {
        guard let media = shot["media"]?.string, let from = shot["from"]?.double, from >= 0 else {
            throw ProjectError.invalid("Clip \(id): each cover needs media and from (source seconds)")
        }
        if let length = shot["seconds"]?.double, length <= 0 { throw ProjectError.invalid("Clip \(id): cover seconds above 0") }
        return Cover(media: media, from: from, seconds: shot["seconds"]?.double)
    }

    static func decodeTitle(_ row: [String: JSONValue], id: String, clips: [Clip]) throws -> Title {
        guard let text = row["text"]?.string, !text.isEmpty else { throw ProjectError.invalid("Title \(id): give text") }
        guard let seconds = row["seconds"]?.double, seconds > 0 else {
            throw ProjectError.invalid("Title \(id): give seconds (how long it shows)")
        }
        let clip = row["clip"]?.string, at = row["at"]?.double
        guard (clip == nil) != (at == nil) else { throw ProjectError.invalid("Title \(id): give clip (with offset) or at") }
        if let clip, !clips.contains(where: { $0.id == clip }) { throw ProjectError.invalid("Title \(id): no clip \(clip)") }
        let (style, textStyle) = splitStyle(row["style"]?.object ?? [:])
        return Title(
            id: id, text: text, clip: clip, offset: row["offset"]?.double ?? 0, at: at, seconds: seconds,
            preset: row["preset"]?.string, style: style, textStyle: textStyle)
    }

    static func orientation(_ width: Int, _ height: Int) -> String {
        guard width > 0, height > 0 else { return "unknown" }
        return width == height ? "square" : width > height ? "landscape" : "portrait"
    }

    /// `plan.sections` as {id, label}.
    static func plannedSections(_ project: Project) -> [(id: String, label: String)] {
        (project["plan"]?.object["sections"]?.array ?? []).compactMap { value in
            guard let id = value.object["id"]?.string else { return nil }
            return (id, value.object["label"]?.string ?? id)
        }
    }
}
