import Foundation

/// Every cut on Main as data (P0-B2, `review.cuts`): its kind (a hard cut or the transition's kind) with length and
/// easing, a gap before it, the framing on each side and whether it stays the same, plus counts and runs per kind.
/// `review.sync` (ReviewSync) times the same cuts against the beats and the words.
public enum ReviewCuts {
    /// Zoom, pan and tilt of `item` at `frame` frames from its start: its keyframes where it has them, else its
    /// transform.
    static func framing(_ item: Item, at frame: Int) -> (zoom: Double, pan: Double, tilt: Double) {
        let transform = item["transform"]?.object ?? [:]
        let motion = item.pictureMotion
        let value = { (property: String, fallback: Double) in motion?.value(property, at: Double(frame)) ?? fallback }
        return (
            value("zoom", transform["zoom"]?.double ?? 1), value("pan", transform["pan"]?.double ?? 0),
            value("tilt", transform["tilt"]?.double ?? 0)
        )
    }

    static func framingJSON(_ framing: (zoom: Double, pan: Double, tilt: Double)) -> JSONValue {
        .object([
            "zoom": .number(ReviewShots.rounded(framing.zoom)), "pan": .number(ReviewShots.rounded(framing.pan)),
            "tilt": .number(ReviewShots.rounded(framing.tilt)),
        ])
    }

    public static func json(_ project: Project) -> JSONValue {
        let fps = project.fps.value
        let main = project.tracks.first { $0.role == TrackRole.main }?.items.sorted { $0.at < $1.at } ?? []
        let transitions = Dictionary(
            project.transitions.map { ($0.toItemID, $0) }, uniquingKeysWith: { first, _ in first })
        var cuts: [JSONValue] = []
        var kinds: [String] = []
        for (left, right) in zip(main, main.dropFirst()) {
            var kind = "hard"
            var row: [String: JSONValue] = [
                "index": .integer(cuts.count), "frame": .integer(right.at),
                "seconds": .number(ReviewShots.rounded(Double(right.at) / fps)), "from": .string(left.id),
                "to": .string(right.id),
            ]
            if let transition = transitions[right.id], transition.fromItemID == left.id {
                kind = transition.kind
                row["transitionFrames"] = .integer(transition.duration)
                row["transitionSeconds"] = .number(ReviewShots.rounded(Double(transition.duration) / fps))
                row["easing"] = .string(transition.easing)
            }
            if right.at > left.end { row["gapFrames"] = .integer(right.at - left.end) }
            let before = framing(left, at: max(0, left.duration - 1)), after = framing(right, at: 0)
            row["framingBefore"] = framingJSON(before)
            row["framingAfter"] = framingJSON(after)
            row["sameFraming"] = .bool(
                left.mediaID != nil && left.mediaID == right.mediaID && abs(before.zoom - after.zoom) < 0.001
                    && abs(before.pan - after.pan) < 0.5 && abs(before.tilt - after.tilt) < 0.5)
            row["kind"] = .string(kind)
            kinds.append(kind)
            cuts.append(.object(row))
        }
        var runs: [JSONValue] = []
        var start = 0
        for index in kinds.indices.dropFirst() + [kinds.count] where index == kinds.count || kinds[index] != kinds[start] {
            if index - start >= 2 {
                runs.append(.object([
                    "kind": .string(kinds[start]), "fromIndex": .integer(start), "toIndex": .integer(index - 1),
                    "count": .integer(index - start),
                ]))
            }
            start = index
        }
        let counts = Dictionary(grouping: kinds, by: { $0 }).mapValues { JSONValue.integer($0.count) }
        return .object([
            "revision": .integer(project.revision), "fps": .number(fps), "cuts": .array(cuts),
            "counts": .object(counts), "runs": .array(runs),
            "sameFraming": .integer(cuts.filter { $0.object["sameFraming"] == .bool(true) }.count),
        ])
    }
}

/// When cuts and other events land against the beat grid and the spoken words (P0-B2, `review.sync`): per event
/// the offset to the nearest beat and to the nearest word edge in frames and milliseconds (positive = after it),
/// and the distribution of those offsets. No limit says what is "on" the beat.
public enum ReviewSync {
    public enum Event: String, CaseIterable, Sendable {
        case cuts, text, sfx
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
            if kinds.contains(.sfx), track.role == TrackRole.sfx {
                result += track.items.map { ($0.at, "sfx", $0.id) }
            }
        }
        return result.sorted { $0.frame == $1.frame ? $0.item < $1.item : $0.frame < $1.frame }
    }

    public static func json(_ project: Project, words: [WordSpan], kinds: Set<Event> = [.cuts]) -> JSONValue {
        let fps = project.fps.value
        let beats = project.beatFrames
        let edges = words.flatMap { [(frame: $0.at, edge: "start", text: $0.text), (frame: $0.end, edge: "end", text: $0.text)] }
            .sorted { $0.frame < $1.frame }
        let milliseconds = { (frames: Int) in JSONValue.number((Double(frames) / fps * 1_000).rounded()) }
        var beatOffsets: [Int] = [], wordOffsets: [Int] = []
        let rows: [JSONValue] = events(project, kinds: kinds).map { event in
            var row: [String: JSONValue] = [
                "frame": .integer(event.frame), "kind": .string(event.kind), "item": .string(event.item),
            ]
            if let beat = nearest(beats, to: event.frame) {
                let offset = event.frame - beat
                beatOffsets.append(offset)
                row["beat"] = .object(["frame": .integer(beat), "offsetFrames": .integer(offset), "offsetMs": milliseconds(offset)])
            }
            if let index = nearestIndex(edges.map(\.frame), to: event.frame) {
                let edge = edges[index], offset = event.frame - edge.frame
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
            "beat": distribution(beatOffsets, fps: fps), "word": distribution(wordOffsets, fps: fps),
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

    /// Count, mean, median, p10, p90 of `offsets` in frames, and how many land at each offset from −6 to +6 frames
    /// with the rest counted as `earlier` and `later`.
    static func distribution(_ offsets: [Int], fps: Double) -> JSONValue {
        guard !offsets.isEmpty else { return .object(["count": .integer(0)]) }
        let sorted = offsets.sorted()
        let percentile = { (share: Double) in sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * share).rounded()))] }
        var counts: [String: JSONValue] = [:]
        for offset in -6...6 { counts[String(offset)] = .integer(offsets.filter { $0 == offset }.count) }
        counts["earlier"] = .integer(offsets.filter { $0 < -6 }.count)
        counts["later"] = .integer(offsets.filter { $0 > 6 }.count)
        let mean = Double(offsets.reduce(0, +)) / Double(offsets.count)
        return .object([
            "count": .integer(offsets.count), "meanFrames": .number(ReviewShots.rounded(mean)),
            "medianFrames": .integer(percentile(0.5)), "p10Frames": .integer(percentile(0.1)),
            "p90Frames": .integer(percentile(0.9)), "medianMs": .number((Double(percentile(0.5)) / fps * 1_000).rounded()),
            "byOffset": .object(counts),
        ])
    }
}
