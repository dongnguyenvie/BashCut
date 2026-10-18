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
    /// The picture fields (`pictureKeys`) the list set on a built item, so a later apply tells them from hand edits.
    static let pictureTag = "planPicture"

    public struct Clip: Sendable {
        public var id: String
        public var media: String
        public var quote: String?
        public var words: (first: Int, last: Int)?
        /// Source seconds; with a quote or words, an edge of that range moved here (either alone).
        public var from: Double?
        public var to: Double?
        public var seconds: Double?
        public var section: String?
        public var speed: Double
        public var volumeDb: Double?
        /// Whether the row gave `speed` (1 included), which then wins over a speed or ramp set by hand.
        public var speedGiven = false
        /// The speech coverage role its items are tagged with (speech, broll, underVO); speech by default for a
        /// clip picked by quote or words.
        public var role: String?
        /// Pictures shown over the clip's sound, in order (B-roll); the last one fills what is left.
        public var cover: [Cover] = []
        /// `zoom`, `pan`, `tilt` for its own picture (a punch-in), as the item's `transform`.
        public var transform: [String: JSONValue] = [:]
        /// The cut transition into the clip from the one before it (#623).
        public var transition: Edge?
        /// `backdrop`, `crop`, `keyframes`, `fill`, `color` of its own picture, as item fields; null clears one set
        /// by hand (which a later apply otherwise keeps).
        public var picture: [String: JSONValue] = [:]
        /// Pictures over the clip on an overlay layer that move with it (picture-in-picture).
        public var overlays: [Overlay] = []
        /// Its own picture framed by source rectangles instead of zoom, pan and tilt (`PlanCut+Focus`).
        public var focus: Focus?
    }

    /// A picture laid over a clip's sound: source seconds `from` of `media`, for `seconds` (the last: the rest).
    public struct Cover: Sendable {
        public var media: String
        public var from: Double
        public var seconds: Double?
        public var transform: [String: JSONValue] = [:]
        public var picture: [String: JSONValue] = [:]
        public var focus: Focus?
    }

    public struct Title: Sendable {
        public var id: String
        public var text: String
        public var clip: String?
        public var offset: Double
        public var at: Double?
        /// A section ID: the title starts with the section's first clip (plus `offset`).
        public var section: String?
        /// How long it shows; nil: to the end of its clip or section.
        public var seconds: Double?
        /// A renderer preset (`TextPreset.all`) or a library text preset's ID.
        public var preset: String?
        /// Item properties other than the text style.
        public var style: [String: JSONValue]
        /// Text style fields (font, size, fill, stroke…), over the preset's.
        public var textStyle: [String: JSONValue] = [:]
        /// Its own In and Out (the item's `enter`, `exit`).
        public var enter: Edge?
        public var exit: Edge?
    }

    /// The `textStyle` fields a title's `style` may give directly.
    public static let textStyleKeys = ItemProperty.all.filter { $0.group == "textStyle" }.map(\.key)
        + ["background", "shadow", "emphasis", "lineFills", "accentBars", "lines"]

    /// A sound effect on the SFX layer: at a clip's or title's start (`on`), a section's start or `at` seconds, plus
    /// `offset` (negative: before it, so a whoosh peaks on the cut), for `seconds` or the whole file.
    public struct Sound: Sendable {
        public var id: String
        public var media: String
        public var on: String?
        public var section: String?
        public var at: Double?
        public var offset: Double
        public var seconds: Double?
        public var volumeDb: Double?
    }

    /// Captions from what the clips say (their media's stored transcripts), in a preset and style.
    public struct Captions: Sendable {
        public var wordStyle: String?
        public var preset: String?
        public var style: [String: JSONValue] = [:]
        public var textStyle: [String: JSONValue] = [:]
        /// Words the transcript got wrong and what the captions say instead ("Tết Sịch" → "Texas"), longest first.
        public var replace: [(from: String, to: String)] = []
        /// The longest caption line for voiceover lines, in characters: a longer line is broken into several cues.
        public var maxChars: Int?
    }

    /// A voiceover line: what it says and the take that says it (`voice.lines` keeps takes; a path picks one, else
    /// the kept take of this text that matched it best). Lines play one after another on the Voiceover layer from
    /// frame 0 (or `at` seconds), `pause` seconds apart.
    public struct Line: Sendable {
        public var id: String
        public var text: String
        /// What the captions show for the line when it differs from what is said (digits for a spelled-out number).
        public var caption: String?
        public var take: String?
        public var section: String?
        public var at: Double?
        public var pause: Double
        public var volumeDb: Double?
    }

    /// A picture placed full canvas over a span: an entry's (`on`: a clip, line, title or graphic), a section's, or
    /// `at` seconds, plus `offset`; for `seconds`, until the end of entry `until`, else to the end of its anchor. On
    /// the Overlay layer, or Main (`track: main`) as the picture of an edit made of graphics. `render` holds a
    /// graphics plugin's inputs (BashCut does not read them).
    public struct Graphic: Sendable {
        public var id: String
        public var media: String?
        public var on: String?
        public var section: String?
        public var at: Double?
        public var offset: Double
        public var seconds: Double?
        public var until: String?
        public var main: Bool
        public var from: Double
        /// The cut transition into it from the picture before it on its layer; its own In and Out.
        public var transition: Edge?
        public var enter: Edge?
        public var exit: Edge?
    }

    public struct Spec: Sendable {
        public var clips: [Clip]
        public var voiceover: [Line] = []
        public var graphics: [Graphic] = []
        public var titles: [Title]
        public var music: Music?
        public var captions: Captions?
        /// Review limits merged over the project's `review` on apply (the recipe's ranges, chosen with the plan).
        public var review: [String: JSONValue]?
        public var sfx: [Sound] = []
        /// Fields the list gave that nothing reads (`unknown-field` warnings), so a typo is not silently ignored.
        public var unknownFields: [Problem] = []
        /// The fact keys each entry cites (`facts: [key]`), checked against the project's facts and claims.
        public var factReferences: [(entry: String, keys: [String])] = []
        /// Entries that could not be read, one error each, all at once (the entries are left out).
        public var invalid: [Problem] = []
        /// Each entry's row by ID (`music` for the bed), so a later apply tells a row changed since plan.cut.
        public var rows: [String: JSONValue] = [:]
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

    static let clipKeys: Set<String> = [
        "id", "media", "quote", "words", "from", "to", "seconds", "section", "speed", "volumeDb", "role", "cover", "facts",
        "transition", "overlays",
    ]
    static let coverKeys: Set<String> = ["media", "from", "seconds"]
    static let soundKeys: Set<String> = ["id", "media", "on", "section", "at", "offset", "seconds", "volumeDb", "facts"]
    static let lineKeys: Set<String> = ["id", "text", "caption", "take", "section", "at", "pause", "volumeDb", "facts"]
    static let graphicKeys: Set<String> = [
        "id", "media", "on", "section", "at", "offset", "seconds", "until", "track", "from", "render", "facts",
        "transition", "enter", "exit",
    ]

    static func unknownSoundFields(_ sounds: [JSONValue], ids: [String]) -> [Problem] {
        unknownEntryFields(sounds, ids: ids, known: soundKeys)
    }

    static func unknownEntryFields(_ entries: [JSONValue], ids: [String], known: Set<String>) -> [Problem] {
        zip(entries, ids).compactMap { value, id in
            let keys = value.object.keys.filter { !known.contains($0) && !noteKeys.contains($0) }.sorted()
            guard !keys.isEmpty else { return nil }
            return Problem(
                id: "unknown-field", severity: "warning", entry: id,
                detail: "Not read, so it changes nothing: \(keys.joined(separator: ", ")); fields here: "
                    + known.sorted().joined(separator: ", "),
                facts: ["fields": .array(keys.map(JSONValue.string))])
        }
    }

    static let titleKeys: Set<String> = [
        "id", "text", "clip", "offset", "at", "section", "seconds", "preset", "style", "facts", "enter", "exit",
    ]
    /// Picture framing a clip or cover may give (a punch-in or reframe), with their item ranges.
    static let transformKeys: [String: ClosedRange<Double>] = ["zoom": 0.01...100, "pan": -65536...65536, "tilt": -65536...65536]
    /// Notes an agent leaves on an entry; read by nobody, never warned about.
    static let noteKeys: Set<String> = ["note", "notes", "why", "reason", "comment"]

    static func unknownFields(_ clips: [JSONValue], titles: [JSONValue], ids: [String]) -> [Problem] {
        var problems: [Problem] = []
        let warn = { (entry: String, keys: [String], known: Set<String>) in
            guard !keys.isEmpty else { return }
            problems.append(Problem(
                id: "unknown-field", severity: "warning", entry: entry,
                detail: "Not read, so it changes nothing: \(keys.joined(separator: ", ")); fields here: "
                    + known.sorted().joined(separator: ", "),
                facts: ["fields": .array(keys.map(JSONValue.string))]))
        }
        let picture = Set(transformKeys.keys).union(pictureKeys).union(focusFields)
        for (index, value) in clips.enumerated() {
            let row = value.object
            let entry = index < ids.count ? ids[index] : "c\(index + 1)"
            warn(entry, row.keys.filter { !clipKeys.contains($0) && !picture.contains($0) && !noteKeys.contains($0) }.sorted(),
                 clipKeys.union(picture))
            for shot in row["cover"]?.array ?? [] {
                warn(entry, shot.object.keys.filter { !coverKeys.contains($0) && !picture.contains($0) && !noteKeys.contains($0) }
                    .sorted(), coverKeys.union(picture))
            }
            for overlay in row["overlays"]?.array ?? [] {
                warn(entry, overlay.object.keys.filter { !overlayKeys.contains($0) && !picture.contains($0) && !noteKeys.contains($0) }
                    .sorted(), overlayKeys.union(picture))
            }
        }
        for (index, value) in titles.enumerated() {
            let entry = clips.count + index < ids.count ? ids[clips.count + index] : "t\(index + 1)"
            warn(entry, value.object.keys.filter { !titleKeys.contains($0) && !noteKeys.contains($0) }.sorted(), titleKeys)
        }
        return problems
    }

    /// `zoom`, `pan`, `tilt` of a clip or cover, checked against their ranges.
    static func decodeTransform(_ row: [String: JSONValue], entry: String) throws -> [String: JSONValue] {
        var transform: [String: JSONValue] = [:]
        for (key, range) in transformKeys.sorted(by: { $0.key < $1.key }) {
            guard let value = row[key], value != .null else { continue }
            guard let number = value.double, range.contains(number) else {
                throw ProjectError.invalid("\(entry): \(key) must be a number in \(range.lowerBound)…\(range.upperBound)")
            }
            transform[key] = .number(number)
        }
        return transform
    }

    /// `captions: {from: "speech", wordStyle, preset, style}`; null or false: none.
    static func decodeCaptions(_ value: JSONValue?) throws -> Captions? {
        guard let value, value != .null, value != .bool(false) else { return nil }
        let row = value.object
        guard (row["from"]?.string ?? "speech") == "speech" else {
            throw ProjectError.invalid("captions.from: speech (captions from what the clips and voiceover lines say)")
        }
        let wordStyle = row["wordStyle"]?.string
        if let wordStyle, !CaptionWords.styles.contains(wordStyle) {
            throw ProjectError.invalid("captions.wordStyle: \(CaptionWords.styles.joined(separator: ", "))")
        }
        let (style, textStyle) = splitStyle(row["style"]?.object ?? [:])
        var replace: [(from: String, to: String)] = []
        if let value = row["replace"], value != .null {
            guard case .object(let pairs) = value, pairs.count <= 100,
                pairs.allSatisfy({ !$0.key.isEmpty && $0.value.string != nil })
            else { throw ProjectError.invalid("captions.replace: {\"heard words\": \"what to show\"}, at most 100") }
            replace = pairs.map { ($0.key, $0.value.string ?? "") }
                .sorted { $0.from.count == $1.from.count ? $0.from < $1.from : $0.from.count > $1.from.count }
        }
        let maxChars = row["maxChars"]?.int
        if let maxChars, !(8...120).contains(maxChars) { throw ProjectError.invalid("captions.maxChars: 8…120 characters") }
        return Captions(
            wordStyle: wordStyle, preset: row["preset"]?.string, style: style, textStyle: textStyle, replace: replace,
            maxChars: maxChars)
    }

    /// Text style fields (straight or nested as `textStyle`) apart from item properties.
    static func splitStyle(_ style: [String: JSONValue]) -> (item: [String: JSONValue], text: [String: JSONValue]) {
        let keys = Set(textStyleKeys)
        var text = style["textStyle"]?.object ?? [:]
        for (key, value) in style where keys.contains(key) { text[key] = value }
        return (style.filter { !keys.contains($0.key) && $0.key != "textStyle" }, text)
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
        guard quote == nil || words == nil else { throw ProjectError.invalid("Clip \(id): give quote or words, not both") }
        if quote == nil, words == nil, from != nil || to != nil {
            guard let from, let to, from >= 0, to > from else { throw ProjectError.invalid("Clip \(id): from < to, in seconds") }
        } else if let from, let to, to <= from {
            // With a quote or words, from/to move that range's edges (either alone).
            throw ProjectError.invalid("Clip \(id): from < to, in seconds")
        }
        if let seconds, seconds <= 0 { throw ProjectError.invalid("Clip \(id): seconds must be above 0") }
        let speed = row["speed"]?.double ?? 1
        guard Project.speedRange.contains(speed) else {
            throw ProjectError.invalid(
                "Clip \(id): speed 0.1…16. For a faster time-lapse, keep less of the source: several short clips "
                    + "(a second or two each) at up to 16× read as one sped-up stretch")
        }
        let cover = try (row["cover"]?.array ?? []).map { try decodeCover($0.object, clip: id) }
        let role = row["role"]?.string
        if let role, !roles.contains(role) { throw ProjectError.invalid("Clip \(id): role is \(roles.joined(separator: ", "))") }
        guard cover.isEmpty || speed == 1 else { throw ProjectError.invalid("Clip \(id): a covered clip plays at 1×") }
        let overlays = try decodeOverlays(row, clip: id, media: media, speed: speed)
        return Clip(
            id: id, media: media, quote: quote, words: words, from: from, to: to, seconds: seconds,
            section: row["section"]?.string, speed: speed, volumeDb: row["volumeDb"]?.double,
            speedGiven: row["speed"].map { $0 != .null } ?? false,
            role: role ?? (quote != nil || words != nil ? "speech" : nil), cover: cover,
            transform: try decodeTransform(row, entry: "Clip \(id)"), picture: try decodePicture(row, entry: "Clip \(id)"),
            overlays: overlays, focus: try decodeFocus(row, entry: "Clip \(id)"))
    }

    static func decodeTitle(_ row: [String: JSONValue], id: String, entries: [String], sections: Set<String>) throws -> Title {
        guard let text = row["text"]?.string, !text.isEmpty else { throw ProjectError.invalid("Title \(id): give text") }
        let seconds = row["seconds"]?.double
        if let seconds, seconds <= 0 { throw ProjectError.invalid("Title \(id): seconds must be above 0") }
        let clip = row["clip"]?.string, at = row["at"]?.double, section = row["section"]?.string
        guard [clip != nil, at != nil, section != nil].filter({ $0 }).count == 1 else {
            throw ProjectError.invalid("Title \(id): give one of clip (a clip or line, with offset), section (with offset) or at")
        }
        if let clip, !entries.contains(clip) { throw ProjectError.invalid("Title \(id): no clip or line \(clip)") }
        if let section, !sections.contains(section) {
            throw ProjectError.invalid("Title \(id): no clip or line is in section \(section)")
        }
        if at != nil, seconds == nil { throw ProjectError.invalid("Title \(id): give seconds with at (how long it shows)") }
        let (style, textStyle) = splitStyle(row["style"]?.object ?? [:])
        return Title(
            id: id, text: text, clip: clip, offset: row["offset"]?.double ?? 0, at: at, section: section, seconds: seconds,
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

// MARK: Decoding the whole list

extension PlanCut {
    /// The list; throws at an entry that cannot be read (every such entry, in one message).
    public static func decode(_ value: JSONValue) throws -> Spec {
        let spec = try decodeAll(value)
        guard spec.invalid.isEmpty else {
            throw ProjectError.invalid(spec.invalid.map(\.detail).joined(separator: "; "))
        }
        return spec
    }

    /// The list with every entry that cannot be read left out and reported in `invalid` (all at once, so one fix
    /// covers them); throws only when the list itself is not one.
    public static func decodeAll(_ value: JSONValue) throws -> Spec {
        guard case .object(let root) = value else { throw ProjectError.invalid("plan.cut must be an object {clips, titles, music}") }
        let clipValues = root["clips"]?.array ?? []
        let lineValues = root["voiceover"]?.array ?? []
        guard !clipValues.isEmpty || !lineValues.isEmpty else {
            throw ProjectError.invalid("plan.cut must list at least one clip or one voiceover line")
        }
        let titleValues = root["titles"]?.array ?? [], graphicValues = root["graphics"]?.array ?? []
        let soundValues = root["sfx"]?.array ?? []
        var invalid: [Problem] = []
        func read<T>(_ entry: String?, _ body: () throws -> T) -> T? {
            do { return try body() } catch {
                invalid.append(Problem(id: "entry-invalid", severity: "error", entry: entry, detail: error.localizedDescription))
                return nil
            }
        }
        var ids = IDs()
        func take(_ values: [JSONValue], _ prefix: String) -> [String?] {
            values.enumerated().map { index, value in
                read(value.object["id"]?.string) { try ids.take(value.object["id"]?.string, prefix, index) }
            }
        }
        let clipIDs = take(clipValues, "c"), lineIDs = take(lineValues, "l"), titleIDs = take(titleValues, "t")
        let graphicIDs = take(graphicValues, "g")
        let sections = Set((clipValues + lineValues).compactMap { $0.object["section"]?.string })
        // An entry that cannot be read still anchors others, so its error is the only one it causes.
        let spoken = (clipIDs + lineIDs).compactMap { $0 }
        let anchors = spoken + (titleIDs + graphicIDs).compactMap { $0 }
        // Each entry by its ID, read with `body`, and its transitions read apart so both errors show.
        func entries<T>(_ values: [JSONValue], _ ids: [String?], _ body: ([String: JSONValue], String) throws -> T) -> [T] {
            zip(values, ids).compactMap { value, id in
                guard let id else { return nil }
                return read(id) { try body(value.object, id) }
            }
        }
        func edge(_ row: [String: JSONValue], _ id: String, _ field: String) -> Edge? {
            read(id) { try decodeEdge(row[field], entry: id, field: field) } ?? nil
        }
        let clips = entries(clipValues, clipIDs) { row, id in
            var clip = try decodeClip(row, id: id)
            clip.transition = edge(row, id, "transition")
            return clip
        }
        let lines = entries(lineValues, lineIDs) { row, id in try decodeLine(row, id: id) }
        let titles = entries(titleValues, titleIDs) { row, id in
            var title = try decodeTitle(row, id: id, entries: spoken, sections: sections)
            (title.enter, title.exit) = (edge(row, id, "enter"), edge(row, id, "exit"))
            return title
        }
        let graphics = entries(graphicValues, graphicIDs) { row, id in
            var graphic = try decodeGraphic(row, id: id, entries: anchors, sections: sections)
            (graphic.transition, graphic.enter, graphic.exit) = (
                edge(row, id, "transition"), edge(row, id, "enter"), edge(row, id, "exit"))
            return graphic
        }
        var music: Music?
        if case .object(let row)? = root["music"] {
            music = read("music") { try Music(row) }
        }
        var review: [String: JSONValue]?
        if let value = root["review"], value != .null {
            review = read("review") {
                guard case .object(let limits) = value else { throw ProjectError.invalid("plan.cut.review: expected {limit: number}") }
                return limits
            }
        }
        let captions = read("captions") { try decodeCaptions(root["captions"]) } ?? nil
        var spec = Spec(clips: clips, titles: titles, music: music, captions: captions, review: review)
        spec.voiceover = lines
        spec.graphics = graphics
        let soundIDs = take(soundValues, "s")
        spec.sfx = entries(soundValues, soundIDs) { row, id in
            try decodeSound(row, id: id, entries: anchors, sections: sections)
        }
        spec.unknownFields = unknownFields(clipValues, titles: titleValues, ids: clipIDs.map { $0 ?? "" } + titleIDs.map { $0 ?? "" })
            + unknownSoundFields(soundValues, ids: soundIDs.map { $0 ?? "" })
            + unknownEntryFields(lineValues, ids: lineIDs.map { $0 ?? "" }, known: lineKeys)
            + unknownEntryFields(graphicValues, ids: graphicIDs.map { $0 ?? "" }, known: graphicKeys)
        spec.factReferences = read(nil) {
            try factReferences([
                (clipValues, clipIDs.map { $0 ?? "" }), (lineValues, lineIDs.map { $0 ?? "" }),
                (titleValues, titleIDs.map { $0 ?? "" }), (graphicValues, graphicIDs.map { $0 ?? "" }),
                (soundValues, soundIDs.map { $0 ?? "" }),
            ])
        } ?? []
        spec.invalid = invalid
        spec.rows = entryRows(value)
        return spec
    }
}
