import Foundation

/// Captions cut from word groups the agent chose (P0-C8, `captions.group`): each group of word indices becomes one
/// caption from its first word's start to its last word's end, with its words timed on it, replacing the captions
/// those words fall in as one undoable edit. The optional rule mode groups by limits the caller must all give; core
/// has no default line length. The result lists each cue's length and reading speed and the gaps and overlaps
/// between cues as facts.
public enum CaptionGrouping {
    public struct Rule: Sendable, Equatable {
        public var maxChars: Int
        public var maxSeconds: Double
        /// A pause at least this long starts a new caption.
        public var breakGapSeconds: Double

        public init(maxChars: Int, maxSeconds: Double, breakGapSeconds: Double) {
            self.maxChars = maxChars
            self.maxSeconds = maxSeconds
            self.breakGapSeconds = breakGapSeconds
        }
    }

    /// Words in order, joined while the line stays within `maxChars` and `maxSeconds` and no pause reaches
    /// `breakGapSeconds`.
    public static func groups(_ words: [ReviewSync.WordSpan], rule: Rule, fps: Double) -> [[Int]] {
        var groups: [[Int]] = []
        var current: [Int] = []
        for (index, word) in words.enumerated() {
            if let first = current.first, let last = current.last {
                let text = (current.map { words[$0].text } + [word.text]).joined(separator: " ")
                let seconds = Double(word.end - words[first].at) / fps
                let gap = Double(word.at - words[last].end) / fps
                if text.count > rule.maxChars || seconds > rule.maxSeconds || gap >= rule.breakGapSeconds {
                    groups.append(current)
                    current = []
                }
            }
            current.append(index)
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// The edit that replaces the captions under the grouped words, and the new cues.
    public static func operation(
        _ project: Project, words: [ReviewSync.WordSpan], groups: [[Int]], author: Author
    ) throws -> (operation: EditOperation, cues: [Item]) {
        guard let track = project.tracks.first(where: { $0.role == TrackRole.captions }) else {
            throw ProjectError.invalid("Caption track is missing")
        }
        let flat = groups.flatMap { $0 }
        guard !groups.isEmpty, groups.allSatisfy({ !$0.isEmpty }), flat.allSatisfy(words.indices.contains),
            flat == flat.sorted(), Set(flat).count == flat.count
        else { throw ProjectError.invalid("groups must be non-empty runs of word indices, in order, each word once") }
        let start = words[flat[0]].at, end = words[flat[flat.count - 1]].end
        let replaced = track.items.filter { $0.at < end && $0.end > start }.sorted { $0.at < $1.at }
        let style = replaced.first
        var cues: [Item] = []
        for group in groups {
            let at = words[group[0]].at, last = words[group[group.count - 1]].end
            var item = Item(id: UUID().uuidString, at: at, duration: max(1, last - at))
            item["text"] = .string(group.map { words[$0].text }.joined(separator: " "))
            for key in ["textPreset", "textStyle", "wordStyle", "captionMedia"] where style?[key] != nil { item[key] = style?[key] }
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
