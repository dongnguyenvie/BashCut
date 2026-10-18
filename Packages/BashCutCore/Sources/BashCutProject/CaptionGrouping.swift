import Foundation

/// Captions cut from word groups the agent chose (P0-C8, `captions.group`): each group of word indices becomes one
/// caption from its first word's start to its last word's end, with its words timed on it, replacing the captions
/// those words fall in as one undoable edit, keeping their look and `plan.apply` marks. The optional rule mode
/// groups by limits the caller must all give; core has no default line length. The result lists each cue's length
/// and reading speed and the gaps and overlaps between cues as facts.
///
/// Grouped cues carry `captionGroup`: the rule they were grouped by, or `{"manual": true}` for chosen groups, so a
/// later `plan.apply` that rebuilds the captions groups the new ones the same way (B3).
public enum CaptionGrouping {
    /// The field on grouped cues that says how they were grouped.
    public static let field = "captionGroup"

    public struct Rule: Sendable, Equatable {
        public var maxChars: Int
        public var maxSeconds: Double
        /// A pause at least this long starts a new caption.
        public var breakGapSeconds: Double
        /// A cut between clips on Main starts a new caption, so one caption never spans two clips.
        public var breakAtCuts: Bool

        public init(maxChars: Int, maxSeconds: Double, breakGapSeconds: Double, breakAtCuts: Bool = true) {
            self.maxChars = maxChars
            self.maxSeconds = maxSeconds
            self.breakGapSeconds = breakGapSeconds
            self.breakAtCuts = breakAtCuts
        }

        /// The rule as the `captionGroup` mark stores it.
        public var json: JSONValue {
            .object([
                "maxChars": .integer(maxChars), "maxSeconds": .number(maxSeconds),
                "breakGapSeconds": .number(breakGapSeconds), "breakAtCuts": .bool(breakAtCuts),
            ])
        }

        /// The rule a `captionGroup` mark stores, or nil for chosen groups.
        public init?(json: JSONValue?) {
            guard let fields = json?.object, let chars = fields["maxChars"]?.int, let seconds = fields["maxSeconds"]?.double,
                let gap = fields["breakGapSeconds"]?.double
            else { return nil }
            self.init(maxChars: chars, maxSeconds: seconds, breakGapSeconds: gap, breakAtCuts: fields["breakAtCuts"] != .bool(false))
        }
    }

    /// The mark chosen groups carry.
    public static let manualMark: JSONValue = .object(["manual": .bool(true)])

    /// Frames where one clip on Main gives way to the next: every start but the first.
    public static func cuts(_ project: Project) -> [Int] {
        let starts = (project.tracks.first { $0.role == TrackRole.main }?.items ?? []).map(\.at)
        let first = starts.min()
        return Array(Set(starts.filter { $0 != first })).sorted()
    }

    /// Words in order, joined while the line stays within `maxChars` and `maxSeconds`, no pause reaches
    /// `breakGapSeconds` and, with `breakAtCuts`, no frame of `cuts` falls between the two words' middles.
    public static func groups(_ words: [ReviewSync.WordSpan], rule: Rule, fps: Double, cuts: [Int] = []) -> [[Int]] {
        var groups: [[Int]] = []
        var current: [Int] = []
        let middle = { (word: ReviewSync.WordSpan) in (word.at + word.end) / 2 }
        for (index, word) in words.enumerated() {
            if let first = current.first, let last = current.last {
                let text = (current.map { words[$0].text } + [word.text]).joined(separator: " ")
                let seconds = Double(word.end - words[first].at) / fps
                let gap = Double(word.at - words[last].end) / fps
                let cut = rule.breakAtCuts && cuts.contains { middle(words[last]) < $0 && $0 <= middle(word) }
                if text.count > rule.maxChars || seconds > rule.maxSeconds || gap >= rule.breakGapSeconds || cut {
                    groups.append(current)
                    current = []
                }
            }
            current.append(index)
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// The edit that replaces the captions under the grouped words (only those of `replacing` when given), and the
    /// new cues; each cue carries `mark` as `captionGroup` when given.
    public static func operation(
        _ project: Project, words: [ReviewSync.WordSpan], groups: [[Int]], author: Author, mark: JSONValue? = nil,
        replacing: Set<String>? = nil
    ) throws -> (operation: EditOperation, cues: [Item]) {
        guard let track = project.tracks.first(where: { $0.role == TrackRole.captions }) else {
            throw ProjectError.invalid("Caption track is missing")
        }
        let flat = groups.flatMap { $0 }
        guard !groups.isEmpty, groups.allSatisfy({ !$0.isEmpty }), flat.allSatisfy(words.indices.contains),
            flat == flat.sorted(), Set(flat).count == flat.count
        else { throw ProjectError.invalid("groups must be non-empty runs of word indices, in order, each word once") }
        let start = words[flat[0]].at, end = words[flat[flat.count - 1]].end
        let replaced = track.items.filter { $0.at < end && $0.end > start && replacing?.contains($0.id) != false }
            .sorted { $0.at < $1.at }
        var cues: [Item] = []
        for (index, group) in groups.enumerated() {
            let at = words[group[0]].at
            // A cue ends where the next one starts: words of a sped-up clip round to frames that overlap by one.
            let next = index + 1 < groups.count ? words[groups[index + 1][0]].at : Int.max
            let last = next > at ? min(words[group[group.count - 1]].end, next) : words[group[group.count - 1]].end
            var item = Item(id: UUID().uuidString, at: at, duration: max(1, last - at))
            // Each cue takes the look and media of the cue its first word was heard in, not the first one replaced:
            // a group of one clip's words must not name another clip's media.
            let heard = words[group[0]]
            let middle = (heard.at + heard.end) / 2
            let style = replaced.first { $0.at <= middle && middle < $0.end } ?? replaced.first
            item["text"] = .string(group.map { words[$0].text }.joined(separator: " "))
            // The plan marks go too, so plan apply still knows the cues as the captions it built (#628).
            for key in ["textPreset", "textStyle", "wordStyle", "captionMedia", PlanCut.tag, PlanCut.captionsTag]
            where style?[key] != nil { item[key] = style?[key] }
            if let mark { item[field] = mark }
            item["words"] = .array(group.map { index in
                let word = words[index]
                return .object([
                    "text": .string(word.text), "at": .integer(max(0, word.at - at)),
                    "dur": .integer(max(1, min(word.end, last) - max(word.at, at))),
                ])
            })
            cues.append(item)
        }
        let operations = replaced.map { EditOperation.delete(item: $0.id, ripple: false) }
            + cues.map { EditOperation.insert(track: track.id, item: $0) }
        return (.group(label: "Group captions", author: author, ops: operations), cues)
    }

    /// Each cue's frames, seconds, characters and characters per second, and the gaps and overlaps between cues.
    public static func facts(_ cues: [Item], fps: Double) -> JSONValue {
        let sorted = cues.sorted { $0.at < $1.at }
        let round = { (value: Double) in JSONValue.number((value * 100).rounded() / 100) }
        var gaps: [JSONValue] = [], overlaps: [JSONValue] = []
        for (index, (left, right)) in zip(sorted, sorted.dropFirst()).enumerated() {
            let gap = right.at - left.end
            if gap > 0 { gaps.append(.object(["after": .integer(index), "frames": .integer(gap)])) }
            if gap < 0 { overlaps.append(.object(["after": .integer(index), "frames": .integer(-gap)])) }
        }
        return .object([
            "cues": .array(sorted.enumerated().map { index, cue in
                let seconds = Double(cue.duration) / fps
                return .object([
                    "index": .integer(index), "id": .string(cue.id), "at": .integer(cue.at), "end": .integer(cue.end),
                    "frames": .integer(cue.duration), "seconds": round(seconds), "chars": .integer(cue.text.count),
                    "cps": round(seconds > 0 ? Double(cue.text.count) / seconds : 0), "text": .string(cue.text),
                ])
            }),
            "gaps": .array(gaps), "overlaps": .array(overlaps),
        ])
    }
}
