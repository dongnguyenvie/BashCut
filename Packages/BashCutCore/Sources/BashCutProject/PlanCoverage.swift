import Foundation

/// The edit plan against what was measured (P1-D3), as facts with no threshold: for each planned shot the described
/// shots in the footage that fit it and the clips that place it (`review.coverage`), and for each script beat whether
/// and where it was heard (`script.check`).
public enum PlanCoverage {
    /// A planned shot fits a described shot when the size matches (if planned) and every `mustShow` name is among the
    /// described subjects (case-insensitive, either containing the other).
    static func fits(_ plan: [String: JSONValue], _ shot: MediaDescription.Shot) -> Bool {
        if let size = plan["size"]?.string, shot.size != size { return false }
        let subjects = shot.subjects.map { $0.lowercased() }
        let names = plan["mustShow"]?.array.compactMap { $0.string?.lowercased() } ?? []
        return names.allSatisfy { name in subjects.contains { $0.contains(name) || name.contains($0) } }
    }

    public static func coverage(_ project: Project) -> JSONValue {
        let planned = project["plan"]?.object["shots"]?.array.map(\.object) ?? []
        let described = project.media.compactMap { media in media.shotDescription.map { (media, $0) } }
        let clips = project.tracks.filter { $0.kind == TrackKind.video }.flatMap(\.items).sorted { $0.at < $1.at }
        let media = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows: [JSONValue] = planned.map { plan in
            let id = plan["id"]?.string ?? ""
            let found = described.flatMap { asset, description in
                description.shots.filter { fits(plan, $0) }.map { shot in
                    JSONValue.object([
                        "media": .string(asset.id), "start": .number(shot.start), "end": .number(shot.end),
                        "size": shot.size.map(JSONValue.string) ?? .null,
                    ])
                }
            }
            let placed = clips.filter { clip in
                if clip["planShot"]?.string == id { return true }
                guard let asset = clip.mediaID.flatMap({ media[$0] }), let description = asset.shotDescription else { return false }
                let span = project.sourceSpan(of: clip, media: asset)
                return description.shot(covering: span.lowerBound, to: span.upperBound).map { fits(plan, $0) } ?? false
            }
            let status = !placed.isEmpty ? "placed" : !found.isEmpty ? "found" : described.isEmpty ? "undescribed" : "missing"
            var row: [String: JSONValue] = [
                "id": .string(id), "status": .string(status), "foundCount": .integer(found.count),
                "found": .array(Array(found.prefix(20))),
                "placed": .array(placed.map { .object(["item": .string($0.id), "at": .integer($0.at)]) }),
            ]
            for key in ["section", "purpose", "size", "mustShow", "source"] { row[key] = plan[key] }
            return .object(row)
        }
        let count = { (status: String) in rows.filter { $0.object["status"] == .string(status) }.count }
        return .object([
            "revision": .integer(project.revision), "shots": .array(rows),
            "summary": .object([
                "planned": .integer(rows.count), "placed": .integer(count("placed")), "found": .integer(count("found")),
                "missing": .integer(count("missing")), "undescribed": .integer(count("undescribed")),
                "describedMedia": .integer(described.count),
            ]),
        ])
    }

    /// Each beat aligned to the words heard on the timeline: the share of its words heard as written, where it was
    /// heard, and in which section marker it starts against the section the plan put it in.
    public static func scriptCheck(_ project: Project, words: [ReviewSync.WordSpan]) -> JSONValue {
        let fps = project.fps.value
        let beats = project["plan"]?.object["beats"]?.array.map(\.object) ?? []
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
