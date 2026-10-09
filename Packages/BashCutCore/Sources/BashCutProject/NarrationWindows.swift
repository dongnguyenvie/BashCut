import Foundation

/// Where narration could go (P0-C3, `narration.windows`): stretches of at least `minSeconds` with no spoken word and no
/// voiceover, each with its entry anchors (the last word before it, the first cut, beat and section inside), the
/// share of it each sound covers (music items, footage sound; the agent decides who owns it), the shots under it with their described facts, the
/// mix level when measured, and with a caller's rate the text budget in the content language's unit.
public enum NarrationWindows {
    public static func json(
        _ project: Project, words: [ReviewSync.WordSpan], minSeconds: Double, rate: Double?, unit: SpeechUnits.Unit,
        levels: MixMeasure.Curve? = nil
    ) -> JSONValue {
        let fps = project.fps.value
        let duration = project.duration
        let voiceover = project.tracks.filter { $0.role == TrackRole.voiceover && !$0.isMuted }.flatMap(\.items)
        let busy = (words.map { ($0.at, $0.end) } + voiceover.map { ($0.at, $0.end) }).sorted { $0.0 < $1.0 }
        var gaps: [(Int, Int)] = []
        var reached = 0
        for (start, end) in busy {
            if start > reached { gaps.append((reached, start)) }
            reached = max(reached, end)
        }
        if duration > reached { gaps.append((reached, duration)) }
        let minimum = Int((minSeconds * fps).rounded())
        let main = project.tracks.first { $0.role == TrackRole.main }?.items.sorted { $0.at < $1.at } ?? []
        let cuts = main.dropFirst().map(\.at)
        let beats = project.beatFrames
        let sections = project.sectionMarkers
        let media = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let seconds = { (frame: Int) in JSONValue.number(ReviewShots.rounded(Double(frame) / fps)) }
        let rows: [JSONValue] = gaps.filter { $0.1 - $0.0 >= max(1, minimum) }.map { start, end in
            var row: [String: JSONValue] = [
                "at": .integer(start), "end": .integer(end), "atSeconds": seconds(start), "endSeconds": seconds(end),
                "seconds": seconds(end - start),
            ]
            let before = words.filter { $0.end <= start }.max { $0.end < $1.end }
            row["anchors"] = .object([
                "afterWord": before.map { .object(["text": .string($0.text), "frame": .integer($0.end)]) } ?? .null,
                "firstCut": cuts.first { $0 >= start && $0 < end }.map(JSONValue.integer) ?? .null,
                "firstBeat": beats.first { $0 >= start && $0 < end }.map(JSONValue.integer) ?? .null,
                "section": sections.last { $0.at <= start }.map { .string($0.label) } ?? .null,
                "sectionStartsInside": sections.first { $0.at > start && $0.at < end }.map { .string($0.label) } ?? .null,
            ])
            row["covered"] = coverage(project, start: start, end: end, media: media)
            row["shots"] = .array(main.filter { $0.at < end && $0.end > start }.map { shot in
                var facts: [String: JSONValue] = ["id": .string(shot.id), "at": .integer(shot.at), "end": .integer(shot.end)]
                if let asset = shot.mediaID.flatMap({ media[$0] }), let description = asset.shotDescription {
                    let span = project.sourceSpan(of: shot, media: asset)
                    if let described = description.shot(covering: span.lowerBound, to: span.upperBound) {
                        facts["described"] = described.factsJSON
                    }
                }
                return .object(facts)
            })
            if let levels {
                let from = Int(Double(start) / fps / levels.step), to = max(from + 1, Int(Double(end) / fps / levels.step))
                let values = (from..<to).map { levels.level($0) }.filter { $0 > MixMeasure.silenceLUFS }
                row["mixLoudness"] = MixMeasure.spread(values)
            }
            if let rate {
                row["budget"] = .object([
                    "rate": .number(rate), "unit": .string(unit.rawValue),
                    "units": .integer(Int((rate * Double(end - start) / fps).rounded(.down))),
                ])
            }
            return .object(row)
        }
        return .object([
            "revision": .integer(project.revision), "minSeconds": .number(minSeconds), "windows": .array(rows),
            "unit": .string(unit.rawValue),
        ])
    }

    /// The share (0–1) of the window that music items and the sound of footage on picture or dialogue layers cover.
    static func coverage(_ project: Project, start: Int, end: Int, media: [String: Media]) -> JSONValue {
        let covered = { (items: [Item]) in
            items.reduce(0) { $0 + max(0, min($1.end, end) - max($1.at, start)) }
        }
        let music = covered(project.tracks.filter { $0.role == TrackRole.music && !$0.isMuted }.flatMap(\.items))
        let footage = covered(project.tracks.filter { ($0.kind == TrackKind.video || $0.role == TrackRole.dialogue) && !$0.isMuted }
            .flatMap(\.items).filter { item in item.mediaID.flatMap { media[$0]?.hasAudio } ?? false })
        let length = Double(max(1, end - start))
        return .object([
            "music": .number(ReviewShots.rounded(min(1, Double(music) / length))),
            "footage": .number(ReviewShots.rounded(min(1, Double(footage) / length))),
        ])
    }
}
