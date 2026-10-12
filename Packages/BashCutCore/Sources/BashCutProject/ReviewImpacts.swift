import Foundation

/// Hits on the whole picture and runs of one sound effect (#518, #519), for `review sync --events impacts,sfx`.
/// Facts only: no limit says how many impacts are too many or which run sounds mechanical.
public enum ReviewImpacts {
    /// Properties of a whole-frame item that make the whole picture jump when they change fast.
    static let pictureProperties = ["zoom", "pan", "tilt", "rotation", "opacity", "color.exposure"]

    public struct Impact: Sendable, Equatable {
        public var frame: Int
        public var frames: Int
        /// `transition`, `keyframes` (a fast change on a Main clip or adjustment layer) or `overlay` (a short
        /// picture over Main).
        public var source: String
        public var item: String
        public var detail: [String: JSONValue]
    }

    /// Every change to the whole picture that lasts at most `window` frames: transitions on Main, keyframe segments
    /// of zoom, pan, tilt, rotation, opacity or exposure on Main clips and adjustment layers, and short pictures on
    /// the other picture layers.
    public static func impacts(_ project: Project, window: Int) -> [Impact] {
        var result: [Impact] = []
        let main = project.tracks.first { $0.role == TrackRole.main }
        for transition in project.transitions where transition.duration <= window {
            guard let to = main?.items.first(where: { $0.id == transition.toItemID }) else { continue }
            result.append(Impact(
                frame: to.at - transition.duration / 2, frames: transition.duration, source: "transition",
                item: transition.id, detail: ["kind": .string(transition.kind)]))
        }
        for track in project.tracks {
            let wholeFrame = track.role == TrackRole.main || track.kind == TrackKind.adjustment
            if wholeFrame {
                for item in track.items {
                    result += segments(item, window: window)
                }
            } else if track.kind == TrackKind.video {
                for item in track.items where item.duration <= window {
                    result.append(Impact(
                        frame: item.at, frames: item.duration, source: "overlay", item: item.id,
                        detail: item.mediaID.map { ["media": .string($0)] } ?? [:]))
                }
            }
        }
        return result.sorted { $0.frame == $1.frame ? $0.item < $1.item : $0.frame < $1.frame }
    }

    /// Keyframe segments of `item` no longer than `window` frames whose value changes, merged per start frame.
    static func segments(_ item: Item, window: Int) -> [Impact] {
        guard let json = item["keyframes"], let motion = try? ItemMotion(json: json) else { return [] }
        var byFrame: [Int: (frames: Int, changes: [String: JSONValue])] = [:]
        for property in pictureProperties {
            guard let keys = motion.keys[property] else { continue }
            for (from, to) in zip(keys, keys.dropFirst()) where to.frame - from.frame <= window && from.value != to.value {
                let start = item.at + from.frame
                guard start >= item.at, start < item.end else { continue }
                var entry = byFrame[start] ?? (0, [:])
                entry.frames = max(entry.frames, to.frame - from.frame)
                entry.changes[property] = .array([.number(rounded(from.value)), .number(rounded(to.value))])
                byFrame[start] = entry
            }
        }
        return byFrame.map { frame, entry in
            Impact(frame: frame, frames: entry.frames, source: "keyframes", item: item.id, detail: ["changes": .object(entry.changes)])
        }
    }

    /// Impacts with their nearest beat (and its strength when known), the spacing to the previous one in beats and
    /// seconds, and a summary: count, per minute, smallest spacing, how many sit on the strongest quarter of beats.
    public static func impactsJSON(_ project: Project, window: Int, beatStrengths: [Int: Double] = [:]) -> JSONValue {
        let fps = project.fps.value
        let beats = project.beatFrames
        let list = impacts(project, window: window)
        let strongest: Double? = {
            let values = beatStrengths.values.sorted()
            return values.isEmpty ? nil : values[Int((Double(values.count - 1) * 0.75).rounded())]
        }()
        var previous: Int?
        var spacings: [Double] = [], beatSpacings: [Int] = []
        var onStrong = 0
        let rows: [JSONValue] = list.map { impact in
            var row: [String: JSONValue] = [
                "frame": .integer(impact.frame), "frames": .integer(impact.frames), "source": .string(impact.source),
                "item": .string(impact.item),
            ]
            row.merge(impact.detail) { current, _ in current }
            if let beat = ReviewSync.nearest(beats, to: impact.frame) {
                var near: [String: JSONValue] = ["frame": .integer(beat), "offsetFrames": .integer(impact.frame - beat)]
                if let strength = beatStrengths[beat] {
                    near["strength"] = .number(rounded(strength))
                    if let strongest, strength >= strongest { onStrong += 1 }
                }
                row["beat"] = .object(near)
            }
            if let last = previous {
                let seconds = Double(impact.frame - last) / fps
                spacings.append(seconds)
                row["secondsSincePrevious"] = .number(rounded(seconds))
                if !beats.isEmpty {
                    let count = beats.filter { $0 > last && $0 <= impact.frame }.count
                    beatSpacings.append(count)
                    row["beatsSincePrevious"] = .integer(count)
                }
            }
            previous = impact.frame
            return .object(row)
        }
        let minutes = Double(project.duration) / fps / 60
        var summary: [String: JSONValue] = [
            "count": .integer(rows.count), "windowFrames": .integer(window),
            "perMinute": .number(minutes > 0 ? rounded(Double(rows.count) / minutes) : 0),
        ]
        if let smallest = spacings.min() { summary["minSpacingSeconds"] = .number(rounded(smallest)) }
        if let smallest = beatSpacings.min() { summary["minSpacingBeats"] = .integer(smallest) }
        if strongest != nil { summary["onStrongestQuarterOfBeats"] = .integer(onStrong) }
        return .object(["summary": .object(summary), "events": .array(rows)])
    }

    /// Runs of one sound file on the sound-effects layers: `minimum` or more placements of the same media whose
    /// starts are at most `gapSeconds` apart. Per run: the items, their frames and gains (volumeDb, 0 when unset),
    /// the intervals between starts, and whether gain and spacing stay the same along the run.
    public static func sfxRunsJSON(_ project: Project, gapSeconds: Double = 2, minimum: Int = 3) -> JSONValue {
        let fps = project.fps.value
        let items = project.tracks.filter { $0.role == TrackRole.sfx }.flatMap(\.items).sorted { $0.at < $1.at }
        let byMedia = Dictionary(grouping: items.filter { $0.mediaID != nil }) { $0.mediaID ?? "" }
        var runs: [(media: String, items: [Item])] = []
        for (media, placements) in byMedia {
            var current: [Item] = []
            for item in placements {
                if let last = current.last, Double(item.at - last.at) / fps > gapSeconds {
                    if current.count >= minimum { runs.append((media, current)) }
                    current = []
                }
                current.append(item)
            }
            if current.count >= minimum { runs.append((media, current)) }
        }
        runs.sort { ($0.items.first?.at ?? 0) < ($1.items.first?.at ?? 0) }
        return .array(runs.map { run in
            let gains = run.items.map { $0["volumeDb"]?.double ?? 0 }
            let intervals = zip(run.items, run.items.dropFirst()).map { $1.at - $0.at }
            return .object([
                "media": .string(run.media), "count": .integer(run.items.count),
                "items": .array(run.items.map { .string($0.id) }), "frames": .array(run.items.map { .integer($0.at) }),
                "gainsDb": .array(gains.map { .number(rounded($0)) }), "intervalsFrames": .array(intervals.map(JSONValue.integer)),
                "constantGain": .bool((gains.max() ?? 0) - (gains.min() ?? 0) < 0.5),
                "constantSpacing": .bool((intervals.max() ?? 0) - (intervals.min() ?? 0) <= 1),
            ])
        })
    }

    static func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
