import Foundation

/// Facts about a run of shots as a sequence (P0-B1): what changes at each cut (with the framing on both sides), how
/// often each size, move and direction occurs, the rhythm of shot lengths overall and per section, and the camera
/// move keyframes make. The same functions read the timeline and a source file (`review.shots --media`). Numbers
/// only: runs, streaks and any limit are the caller's to compute.
extension ReviewShots {
    /// One shot in a sequence: its length, where it comes from and what `media.describe` says it shows.
    struct SequenceShot {
        var seconds: Double
        var media: String?
        /// Source seconds the shot plays, when it plays a media.
        var source: ClosedRange<Double>?
        /// Source frame length of its media, so "adjacent" means within one frame.
        var sourceFrame: Double
        var facts: MediaDescription.Shot?
    }

    /// What changes at the cut from `left` to `right`: whether both play the same media and, if so, the same setup
    /// (overlapping or adjacent source) and the source jump; size, move and direction from → to when described.
    static func cut(from left: SequenceShot, to right: SequenceShot) -> JSONValue {
        let sameMedia = left.media != nil && left.media == right.media
        var row: [String: JSONValue] = ["sameMedia": .bool(sameMedia)]
        if sameMedia, let before = left.source, let after = right.source {
            let gap = after.lowerBound - before.upperBound
            row["sourceGapSeconds"] = .number(rounded(gap))
            let overlaps = after.lowerBound < before.upperBound && before.lowerBound < after.upperBound
            row["sameSetup"] = .bool(overlaps || abs(gap) <= left.sourceFrame + 0.000_1)
        } else {
            row["sameSetup"] = .bool(false)
        }
        for (key, value) in [("size", \MediaDescription.Shot.size), ("move", \.move), ("direction", \.direction)] {
            let from = left.facts?[keyPath: value], to = right.facts?[keyPath: value]
            guard from != nil || to != nil else { continue }
            row[key] = .object(["from": from.map(JSONValue.string) ?? .null, "to": to.map(JSONValue.string) ?? .null])
        }
        return .object(row)
    }

    /// How often each size, move and direction occurs among the described shots.
    static func shares(_ shots: [SequenceShot]) -> JSONValue {
        let described = shots.compactMap(\.facts)
        func share(_ value: KeyPath<MediaDescription.Shot, String?>) -> JSONValue {
            let values = described.compactMap { $0[keyPath: value] }
            let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
            return .object(counts.mapValues { count in
                .object(["count": .integer(count), "share": .number(rounded(Double(count) / Double(max(1, described.count))))])
            })
        }
        return .object([
            "described": .integer(described.count), "shots": .integer(shots.count), "size": share(\.size),
            "move": share(\.move), "direction": share(\.direction),
        ])
    }

    /// Mean, median, coefficient of variation (deviation over mean), cuts per minute over `span` seconds and the
    /// share of the most common length bin (the `media.analysis` histogram bins).
    static func rhythm(_ lengths: [Double], span: Double) -> JSONValue {
        guard !lengths.isEmpty else { return .object(["count": .integer(0)]) }
        var result = summary(seconds: lengths, span: span).object
        result["cv"] = .number(rounded(cv(lengths)))
        let bins = MediaAnalysis.histogram(lengths).array
        if let mode = bins.max(by: { ($0.object["count"]?.int ?? 0) < ($1.object["count"]?.int ?? 0) }) {
            var bin = mode.object
            bin["share"] = .number(rounded(Double(bin["count"]?.int ?? 0) / Double(lengths.count)))
            result["mode"] = .object(bin)
        }
        return .object(result)
    }

    static func cv(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot() / mean
    }

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

    /// The framing on the last frame of `left` and the first of `right` {zoom, pan, tilt}, and whether it stays the
    /// same (same media, zoom within 0.001, pan and tilt within half a pixel).
    static func framingChange(from left: Item, to right: Item) -> [String: JSONValue] {
        let before = framing(left, at: max(0, left.duration - 1)), after = framing(right, at: 0)
        let json = { (framing: (zoom: Double, pan: Double, tilt: Double)) -> JSONValue in
            .object(["zoom": .number(rounded(framing.zoom)), "pan": .number(rounded(framing.pan)),
                     "tilt": .number(rounded(framing.tilt))])
        }
        return [
            "framingBefore": json(before), "framingAfter": json(after),
            "sameFraming": .bool(
                left.mediaID != nil && left.mediaID == right.mediaID && abs(before.zoom - after.zoom) < 0.001
                    && abs(before.pan - after.pan) < 0.5 && abs(before.tilt - after.tilt) < 0.5),
        ]
    }

    /// The camera move keyframes make on an item: per animated picture property, the value at its first and last
    /// key, the change per second between them (zoom as % of the start, pan/tilt in output pixels, rotation in
    /// degrees, opacity in units) and the ease (the first key's, or `mixed`). Nil without picture keys.
    static func cameraMove(_ item: Item, fps: Double) -> JSONValue? {
        guard let motion = item.pictureMotion else { return nil }
        var rows: [JSONValue] = []
        for property in ItemMotion.pictureProperties {
            guard let keys = motion.keys[property], keys.count >= 2, let first = keys.first, let last = keys.last,
                last.frame > first.frame
            else { continue }
            let seconds = Double(last.frame - first.frame) / fps
            let change = property == "zoom" && first.value != 0
                ? (last.value / first.value - 1) * 100 : last.value - first.value
            let eases = Set(keys.dropLast().map(\.ease.rawValue))
            rows.append(.object([
                "property": .string(property), "from": .number(rounded(first.value)), "to": .number(rounded(last.value)),
                "perSecond": .number(rounded(change / seconds)), "seconds": .number(rounded(seconds)),
                "ease": .string(eases.count == 1 ? eases.first ?? "mixed" : "mixed"),
                "unit": .string(property == "zoom" ? "%" : property == "rotation" ? "deg" : property == "opacity" ? "" : "px"),
            ]))
        }
        return rows.isEmpty ? nil : .array(rows)
    }

    /// Rhythm per section marker: the shots that start in each section.
    static func sectionRhythm(_ main: [Item], sections: [TimelineMarker], fps: Double) -> JSONValue {
        guard !sections.isEmpty else { return .array([]) }
        var rows: [JSONValue] = []
        for (index, section) in sections.enumerated() {
            let end = index + 1 < sections.count ? sections[index + 1].at : Int.max
            let inside = main.filter { $0.at >= section.at && $0.at < end }
            var row = rhythm(
                inside.map { Double($0.duration) / fps },
                span: Double((inside.last?.end ?? 0) - (inside.first?.at ?? 0)) / fps
            ).object
            row["label"] = .string(section.label)
            row["at"] = .integer(section.at)
            rows.append(.object(row))
        }
        return .array(rows)
    }

    /// The same sequence facts for a source file's measured shots (`media.analyze`), with the shots
    /// `media.describe` wrote: `review.shots --media`.
    public static func json(media: Media, record: MediaAnalysis, minScore: Double) -> JSONValue {
        let description = media.shotDescription
        let cuts = record.cuts(minScore: minScore)
        let (rows, lengths) = record.shotsJSON(cuts)
        let spans = record.shotSpans(minScore: minScore) ?? []
        let sequence = spans.map { span in
            SequenceShot(
                seconds: span.end - span.start, media: media.id, source: span.start...span.end,
                sourceFrame: 1 / max(1, record.picture?.fps ?? 30),
                facts: description?.shot(covering: span.start, to: span.end))
        }
        var shots: [JSONValue] = []
        for (index, row) in rows.enumerated() {
            var shot = row.object
            if index < sequence.count, let facts = sequence[index].facts { shot["described"] = facts.factsJSON }
            if index > 0, index < sequence.count { shot["cut"] = cut(from: sequence[index - 1], to: sequence[index]) }
            shots.append(.object(shot))
        }
        return .object([
            "media": .string(media.id), "shots": .array(shots), "shares": shares(sequence),
            "rhythm": rhythm(lengths, span: Double(record.picture?.frames ?? 0) / (record.picture?.fps ?? 1)),
        ])
    }
}
