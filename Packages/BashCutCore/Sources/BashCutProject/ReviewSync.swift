import Foundation

/// When cuts and other events land against the beat grid and the spoken words (P0-B2, `review.sync`): per event
/// the offset to the nearest beat and to the nearest word edge in frames and milliseconds (positive = after it),
/// and count, mean and median of those offsets (with `bins`, also p10/p90 and counts per offset). No limit says what
/// is "on" the beat.
public enum ReviewSync {
    public enum Event: String, CaseIterable, Sendable {
        /// `captions`: each caption cue's start against the nearest word edge (P1-E7: a shifted caption track).
        case cuts, text, sfx, captions
    }

    /// A word on the timeline, in frames.
    public struct WordSpan: Sendable, Equatable {
        public var at: Int
        public var end: Int
        public var text: String

        public init(at: Int, end: Int, text: String) {
            self.at = at
            self.end = end
            self.text = text
        }
    }

    static func events(_ project: Project, kinds: Set<Event>) -> [(frame: Int, kind: String, item: String)] {
        var result: [(frame: Int, kind: String, item: String)] = []
        if kinds.contains(.cuts) {
            let main = project.tracks.first { $0.role == TrackRole.main }?.items.sorted { $0.at < $1.at } ?? []
            result += main.dropFirst().map { ($0.at, "cut", $0.id) }
        }
        for track in project.tracks {
            if kinds.contains(.text), track.kind == TrackKind.text, track.role != TrackRole.captions {
                result += track.items.map { ($0.at, "text", $0.id) }
            }
            if kinds.contains(.captions), track.role == TrackRole.captions {
                result += track.items.map { ($0.at, "caption", $0.id) }
            }
            if kinds.contains(.sfx), track.role == TrackRole.sfx {
                result += track.items.map { ($0.at, "sfx", $0.id) }
            }
        }
        return result.sorted { $0.frame == $1.frame ? $0.item < $1.item : $0.frame < $1.frame }
    }

    public static func json(
        _ project: Project, words: [WordSpan], kinds: Set<Event> = [.cuts], bins: Bool = false
    ) -> JSONValue {
        let fps = project.fps.value
        let beats = project.beatFrames
        let edges = words.flatMap { [(frame: $0.at, edge: "start", text: $0.text), (frame: $0.end, edge: "end", text: $0.text)] }
            .sorted { $0.frame < $1.frame }
        let milliseconds = { (frames: Int) in JSONValue.number((Double(frames) / fps * 1_000).rounded()) }
        var beatOffsets: [Int] = [], wordOffsets: [Int] = []
        let texts = Dictionary(project.tracks.flatMap(\.items).map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        let rows: [JSONValue] = events(project, kinds: kinds).map { event in
            var row: [String: JSONValue] = [
                "frame": .integer(event.frame), "kind": .string(event.kind), "item": .string(event.item),
            ]
            if let beat = nearest(beats, to: event.frame) {
                let offset = event.frame - beat
                beatOffsets.append(offset)
                row["beat"] = .object(["frame": .integer(beat), "offsetFrames": .integer(offset), "offsetMs": milliseconds(offset)])
            }
            // A caption is timed against the start of the word it begins with, where that word is said nearest.
            let first = event.kind == "caption" ? SpeechUnits.tokens(texts[event.item] ?? "").first.map(SpeechUnits.normalized) : nil
            let matching = first.map { token in
                edges.filter { $0.edge == "start" && SpeechUnits.normalized($0.text) == token }
            } ?? []
            let candidates = matching.isEmpty ? edges : matching
            if let index = nearestIndex(candidates.map(\.frame), to: event.frame) {
                let edge = candidates[index], offset = event.frame - edge.frame
                wordOffsets.append(offset)
                row["word"] = .object([
                    "frame": .integer(edge.frame), "edge": .string(edge.edge), "text": .string(edge.text),
                    "offsetFrames": .integer(offset), "offsetMs": milliseconds(offset),
                    "inside": .bool(words.contains { $0.at < event.frame && event.frame < $0.end }),
                ])
            }
            return .object(row)
        }
        return .object([
            "revision": .integer(project.revision), "fps": .number(fps), "beats": .integer(beats.count),
            "words": .integer(words.count), "events": .array(rows),
            "beat": distribution(beatOffsets, fps: fps, bins: bins), "word": distribution(wordOffsets, fps: fps, bins: bins),
        ])
    }

    static func nearest(_ frames: [Int], to frame: Int) -> Int? { nearestIndex(frames, to: frame).map { frames[$0] } }

    /// Index of the value closest to `frame` in sorted `frames`; the earlier one on a tie.
    static func nearestIndex(_ frames: [Int], to frame: Int) -> Int? {
        guard !frames.isEmpty else { return nil }
        let after = frames.partitioningIndex { $0 >= frame }
        if after == frames.count { return frames.count - 1 }
        if after == 0 { return 0 }
        return frame - frames[after - 1] <= frames[after] - frame ? after - 1 : after
    }

    /// Count, mean and median of `offsets` in frames; with `bins`, also p10, p90 and how many land at each offset
    /// from −6 to +6 frames with the rest counted as `earlier` and `later`.
    static func distribution(_ offsets: [Int], fps: Double, bins: Bool) -> JSONValue {
        guard !offsets.isEmpty else { return .object(["count": .integer(0)]) }
        let sorted = offsets.sorted()
        let percentile = { (share: Double) in sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * share).rounded()))] }
        let mean = Double(offsets.reduce(0, +)) / Double(offsets.count)
        var result: [String: JSONValue] = [
            "count": .integer(offsets.count), "meanFrames": .number(ReviewShots.rounded(mean)),
            "medianFrames": .integer(percentile(0.5)), "medianMs": .number((Double(percentile(0.5)) / fps * 1_000).rounded()),
        ]
        guard bins else { return .object(result) }
        var counts: [String: JSONValue] = [:]
        for offset in -6...6 { counts[String(offset)] = .integer(offsets.filter { $0 == offset }.count) }
        counts["earlier"] = .integer(offsets.filter { $0 < -6 }.count)
        counts["later"] = .integer(offsets.filter { $0 > 6 }.count)
        result["p10Frames"] = .integer(percentile(0.1))
        result["p90Frames"] = .integer(percentile(0.9))
        result["byOffset"] = .object(counts)
        return .object(result)
    }
}
