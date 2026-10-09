import Foundation

/// What the timeline plays and says, as facts with no threshold (P1-D3, flexibility audit A8/A9): which described
/// source shot each video clip plays (`review.coverage`; the agent joins it with its plan), and for each script beat
/// whether and where it was heard (`script.check`).
public enum PlanCoverage {
    /// Every clip on the video tracks in time order: item, track, at/end, media, its `planShot` field when set, and
    /// the `media.describe` shot it plays {index, start, end and the described facts}, or null when its media has no
    /// description covering it.
    public static func coverage(_ project: Project) -> JSONValue {
        let media = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var clips: [(track: Track, clip: Item)] = []
        for track in project.tracks where track.kind == TrackKind.video {
            clips += track.items.map { (track, $0) }
        }
        clips.sort { $0.clip.at == $1.clip.at ? $0.clip.id < $1.clip.id : $0.clip.at < $1.clip.at }
        var described = 0
        let rows: [JSONValue] = clips.map { track, clip in
            var row: [String: JSONValue] = [
                "item": .string(clip.id), "track": .string(track.id), "at": .integer(clip.at), "end": .integer(clip.end),
                "media": clip.mediaID.map(JSONValue.string) ?? .null, "described": .null,
            ]
            if let planShot = clip["planShot"] { row["planShot"] = planShot }
            if let asset = clip.mediaID.flatMap({ media[$0] }), let description = asset.shotDescription {
                let span = project.sourceSpan(of: clip, media: asset)
                if let shot = description.shot(covering: span.lowerBound, to: span.upperBound) {
                    var facts = shot.factsJSON.object
                    facts["index"] = description.shots.firstIndex(of: shot).map(JSONValue.integer) ?? .null
                    facts["start"] = .number(shot.start)
                    facts["end"] = .number(shot.end)
                    row["described"] = .object(facts)
                    described += 1
                }
            }
            return .object(row)
        }
        return .object([
            "revision": .integer(project.revision), "clips": .array(rows),
            "summary": .object([
                "clips": .integer(rows.count), "described": .integer(described),
                "describedMedia": .integer(project.media.filter { $0.shotDescription != nil }.count),
            ]),
        ])
    }

    /// Each beat ({id, text, section}; default the plan's beats) aligned to the words heard on the timeline: the share
    /// of its words heard as written, where it was heard, and in which section marker it starts against the section
    /// the beat names.
    public static func scriptCheck(
        _ project: Project, words: [ReviewSync.WordSpan], beats given: [[String: JSONValue]]? = nil
    ) -> JSONValue {
        let fps = project.fps.value
        let beats = given ?? project["plan"]?.object["beats"]?.array.map(\.object) ?? []
        let heard = words.sorted { $0.at < $1.at }.map {
            CaptionWords.Timed(text: $0.text, start: Double($0.at) / fps, end: Double($0.end) / fps)
        }
        let texts = beats.map { $0["text"]?.string ?? "" }
        let alignment = TextAlignment.align(texts.joined(separator: " "), to: heard)
        let markers = project.sectionMarkers
        var labels: [String: String] = [:]
        for section in project["plan"]?.object["sections"]?.array.map(\.object) ?? [] {
            if let id = section["id"]?.string, let label = section["label"]?.string { labels[id] = label }
        }
        var index = 0
        let rows: [JSONValue] = zip(beats, texts).map { beat, text in
            let count = SpeechUnits.tokens(text).count
            let part = alignment.words[index..<min(alignment.words.count, index + count)]
            index += count
            let matched = part.filter { $0.kind == "match" }
            var row: [String: JSONValue] = [
                "id": beat["id"] ?? .null, "text": .string(text), "words": .integer(count),
                "heardShare": .number(count == 0 ? 0 : (Double(matched.count) / Double(count) * 100).rounded() / 100),
                "plannedSection": beat["section"] ?? .null,
            ]
            if let first = matched.first, let last = matched.last {
                let at = Int((first.start * fps).rounded()), end = Int((last.end * fps).rounded())
                row["at"] = .integer(at)
                row["end"] = .integer(end)
                let marker = markers.last { $0.at <= at }
                row["section"] = marker.map { .object(["id": .string($0.id), "label": .string($0.label)]) } ?? .null
                if let planned = beat["section"]?.string, let marker {
                    row["inPlannedSection"] = .bool(
                        planned == marker.id || planned == marker.label || labels[planned] == marker.label)
                }
            }
            row["unmatched"] = .array(part.filter { $0.kind != "match" }.map { .string($0.text) })
            return .object(row)
        }
        return .object([
            "revision": .integer(project.revision), "beats": .array(rows), "heardWords": .integer(heard.count),
            "extraWords": .integer(alignment.extra.count),
            "similarity": .number((alignment.similarity * 100).rounded() / 100),
        ])
    }
}
