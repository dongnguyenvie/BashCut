import Foundation

/// What `plan.check` reports per entry: facts, not verdicts.
extension PlanCut {
    /// Per clip: where it plays, its source range and edges, the described shot (or its covers) and orientation
    /// against the canvas; per title: chars per second; and the problems those facts show.
    public static func facts(
        _ spec: Spec, clips: [Resolved], placements: [Placement], on project: Project
    ) -> (clips: [JSONValue], titles: [JSONValue], problems: [Problem]) {
        var problems: [Problem] = []
        var previous: (media: String, size: String)?
        var rows: [JSONValue] = []
        for resolved in clips {
            guard let placement = placements.first(where: { $0.id == resolved.clip.id }),
                let media = project.media.first(where: { $0.id == resolved.clip.media })
            else { continue }
            var row = clipRow(resolved, placement: placement, fps: project.fps.value)
            problems += edgeProblems(resolved)
            if resolved.clip.cover.isEmpty {
                problems += pictureFacts(resolved, media: media, project: project, previous: &previous, into: &row)
            } else {
                problems += coverFacts(resolved.clip, project: project, into: &row)
                previous = nil
            }
            rows.append(.object(row))
        }
        let titles = spec.titles.compactMap { title -> JSONValue? in
            guard let placement = placements.first(where: { $0.id == title.id }) else { return nil }
            let characters = title.text.filter { !$0.isWhitespace }.count
            let seconds = Double(placement.end - placement.at) / project.fps.value
            return .object([
                "id": .string(title.id), "text": .string(title.text), "at": rounded(Double(placement.at) / project.fps.value),
                "seconds": rounded(seconds), "charsPerSecond": rounded(Double(characters) / max(seconds, 0.01)),
            ])
        }
        return (rows, titles, problems)
    }

    static func rounded(_ value: Double) -> JSONValue { .number((value * 100).rounded() / 100) }

    static func clipRow(_ resolved: Resolved, placement: Placement, fps: Double) -> [String: JSONValue] {
        let clip = resolved.clip
        var row: [String: JSONValue] = [
            "id": .string(clip.id), "media": .string(clip.media), "from": rounded(resolved.from), "to": rounded(resolved.to),
            "at": rounded(Double(placement.at) / fps), "end": rounded(Double(placement.end) / fps),
            "seconds": rounded(Double(placement.end - placement.at) / fps),
        ]
        if let section = clip.section { row["section"] = .string(section) }
        if clip.speed != 1 { row["speed"] = .number(clip.speed) }
        for key in ["text", "in", "out", "matched"] { row[key] = resolved.facts[key] }
        return row
    }

    static func edgeProblems(_ resolved: Resolved) -> [Problem] {
        ["in", "out"].filter { resolved.facts[$0]?.object["midWord"]?.bool == true }.map { edge in
            Problem(
                id: "cut-inside-word", severity: "warning", entry: resolved.clip.id,
                detail: "The clip's \(edge) edge falls inside a word", facts: ["edge": resolved.facts[edge] ?? .null])
        }
    }

    /// The clip's own picture: orientation, the described shot, and the same media and size as the clip before.
    static func pictureFacts(
        _ resolved: Resolved, media: Media, project: Project, previous: inout (media: String, size: String)?,
        into row: inout [String: JSONValue]
    ) -> [Problem] {
        let id = resolved.clip.id
        var problems = orientationProblems(media, entry: id, project: project, into: &row)
        guard let shot = media.shotDescription?.shot(covering: resolved.from, to: resolved.to) else {
            previous = nil
            return problems
        }
        row["described"] = .object(["size": shot.size.map(JSONValue.string) ?? .null, "start": rounded(shot.start), "end": rounded(shot.end)])
        if let size = shot.size, let before = previous, before.media == media.id, before.size == size {
            problems.append(Problem(
                id: "same-framing", severity: "info", entry: id,
                detail: "Same media and described size (\(size)) as the clip before: a jump cut unless reframed",
                facts: ["size": .string(size)]))
        }
        previous = shot.size.map { (media.id, $0) }
        return problems
    }

    /// The picture is the covers': their shapes count, the clip's own shot is not seen.
    static func coverFacts(_ clip: Clip, project: Project, into row: inout [String: JSONValue]) -> [Problem] {
        var problems: [Problem] = []
        row["cover"] = .array(clip.cover.map { shot in
            var cover: [String: JSONValue] = ["media": .string(shot.media), "from": rounded(shot.from)]
            if let seconds = shot.seconds { cover["seconds"] = rounded(seconds) }
            if let picture = project.media.first(where: { $0.id == shot.media }) {
                problems += orientationProblems(picture, entry: clip.id, project: project, into: &cover)
            }
            return .object(cover)
        })
        return problems
    }

    /// Writes the media's orientation into `row`; a shape other than the canvas's is noted.
    static func orientationProblems(
        _ media: Media, entry: String, project: Project, into row: inout [String: JSONValue]
    ) -> [Problem] {
        let shape = orientation(media.width ?? 0, media.height ?? 0)
        let canvas = orientation(project.width, project.height)
        row["orientation"] = .string(shape)
        guard shape != "unknown", canvas != "unknown", shape != canvas else { return [] }
        return [Problem(
            id: "orientation-mix", severity: "info", entry: entry,
            detail: "\(shape) \(media.id) on a \(canvas) canvas: cropped or boxed unless reframed",
            facts: ["media": .string(shape), "canvas": .string(canvas)])]
    }
}
