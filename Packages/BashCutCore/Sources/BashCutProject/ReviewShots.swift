import Foundation

/// The shots on Main as data for the agent (`review.shots`, #464): timing, source, framing and speed from the
/// timeline, motion from a picture measurement of the same revision, and the facts `media.describe` stored for the
/// source shot it plays (`described`). No verdicts: a skill compares the numbers with the range its genre allows.
public enum ReviewShots {
    public static func json(_ project: Project, picture: ReviewPicture? = nil, summary: Bool = false) -> JSONValue {
        let fps = project.fps.value
        let measured = picture.flatMap { $0.revision == project.revision ? $0 : nil }
        let main = project.tracks.first { $0.role == "main" }?.items.sorted { $0.at < $1.at } ?? []
        let media = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let descriptions = media.compactMapValues(\.shotDescription)
        let transitions = Dictionary(
            project.transitions.map { ($0.toItemID, $0) }, uniquingKeysWith: { first, _ in first })
        var previous: Item?
        let shots: [JSONValue] = main.enumerated().map { index, shot in
            defer { previous = shot }
            var row: [String: JSONValue] = [
                "index": .integer(index), "id": .string(shot.id), "at": .integer(shot.at),
                "atSeconds": .number(rounded(Double(shot.at) / fps)), "duration": .integer(shot.duration),
                "seconds": .number(rounded(Double(shot.duration) / fps)), "speed": .number(shot.speed),
            ]
            row.merge(source(shot, media: media, fps: fps)) { _, new in new }
            if let mediaID = shot.mediaID, let asset = media[mediaID], let description = descriptions[mediaID] {
                let span = project.sourceSpan(of: shot, media: asset)
                if let described = description.shot(covering: span.lowerBound, to: span.upperBound) {
                    var facts = described.factsJSON.object
                    facts["start"] = .number(rounded(described.start))
                    facts["end"] = .number(rounded(described.end))
                    row["described"] = .object(facts)
                }
            }
            if let left = previous {
                row["gapBefore"] = .integer(shot.at - left.end)
                if let transition = transitions[shot.id], transition.fromItemID == left.id {
                    row["transitionIn"] = .object([
                        "kind": .string(transition.kind), "duration": .integer(transition.duration),
                    ])
                } else if let difference = measured?.cuts[shot.id] {
                    row["cutDifference"] = .number(rounded(difference))
                }
            }
            if let measured { row["motion"] = motion(measured, from: shot.at, to: shot.end) }
            return .object(row)
        }
        var result: [String: JSONValue] = [
            "revision": .integer(project.revision), "fps": .number(fps), "shots": .array(shots),
            "pictureMeasured": .bool(measured != nil),
        ]
        if measured == nil, let picture { result["pictureRevision"] = .integer(picture.revision) }
        if summary { result["summary"] = Self.summary(main, fps: fps) }
        return .object(result)
    }

    /// Source media and in-point, framing, keyframed properties and the freeze/reverse fields of a shot.
    static func source(_ shot: Item, media: [String: Media], fps: Double) -> [String: JSONValue] {
        var row: [String: JSONValue] = [:]
        if let mediaID = shot.mediaID {
            row["media"] = .string(mediaID)
            let source = media[mediaID]
            if let kind = source?.kind, !kind.isEmpty { row["mediaKind"] = .string(kind) }
            row["sourceIn"] = .integer(shot.sourceIn)
            let sourceFPS = source.map(\.fps.value).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? fps
            row["sourceInSeconds"] = .number(rounded(Double(shot.sourceIn) / sourceFPS))
        }
        let transform = shot["transform"]?.object ?? [:]
        row["zoom"] = .number(transform["zoom"]?.double ?? 1)
        if !transform.isEmpty { row["transform"] = .object(transform) }
        if let keyframes = shot["keyframes"]?.object, !keyframes.isEmpty {
            row["keyframed"] = .array(keyframes.keys.sorted().map(JSONValue.string))
        }
        for key in ["freezeFrame", "reverse"] where shot[key] != nil { row[key] = shot[key] }
        return row
    }

    /// Mean sample change and the largest one-cell change inside the shot. The first sample of a shot compares across
    /// the cut, so it is left out; a shot with no sample inside it has null motion.
    static func motion(_ picture: ReviewPicture, from: Int, to: Int) -> JSONValue {
        let inside = picture.samples.filter { $0.frame > from && $0.frame < to }
        guard !inside.isEmpty else { return .null }
        return .object([
            "mean": .number(rounded(inside.map(\.change).reduce(0, +) / Double(inside.count))),
            "peak": .number(rounded(inside.map(\.peak).max() ?? 0)),
            "samples": .integer(inside.count),
        ])
    }

    /// Count, total, mean, median, minimum and maximum shot length in seconds, and cuts per minute over the span from
    /// the first shot's start to the last one's end.
    static func summary(_ shots: [Item], fps: Double) -> JSONValue {
        guard let first = shots.first, let last = shots.last else { return .object(["count": .integer(0)]) }
        return summary(seconds: shots.map { Double($0.duration) / fps }, span: Double(last.end - first.at) / fps)
    }

    /// The same statistics for shot lengths in seconds over `span` seconds; `media.analysis` uses them for a source
    /// file, so a reference video and the timeline are summarised alike.
    static func summary(seconds lengths: [Double], span: Double) -> JSONValue {
        let seconds = lengths.sorted()
        guard !seconds.isEmpty else { return .object(["count": .integer(0)]) }
        let middle = seconds.count / 2
        let median = seconds.count % 2 == 0 ? (seconds[middle - 1] + seconds[middle]) / 2 : seconds[middle]
        return .object([
            "count": .integer(seconds.count), "totalSeconds": .number(rounded(seconds.reduce(0, +))),
            "meanSeconds": .number(rounded(seconds.reduce(0, +) / Double(seconds.count))),
            "medianSeconds": .number(rounded(median)), "minSeconds": .number(rounded(seconds[0])),
            "maxSeconds": .number(rounded(seconds[seconds.count - 1])),
            "cutsPerMinute": .number(span > 0 ? rounded(Double(seconds.count - 1) / span * 60) : 0),
        ])
    }

    static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
}
