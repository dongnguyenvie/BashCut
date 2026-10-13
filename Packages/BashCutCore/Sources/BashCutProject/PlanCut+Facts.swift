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
        // A punch-in (the clip's zoom) is a framing of its own.
        let zoom = resolved.clip.transform["zoom"]?.double ?? 1
        let framing = shot.size.map { zoom == 1 ? $0 : "\($0)@\(zoom)" }
        if let size = shot.size, let framing, let before = previous, before.media == media.id, before.size == framing {
            problems.append(Problem(
                id: "same-framing", severity: "info", entry: id,
                detail: "Same media and described size (\(size)) as the clip before: a jump cut unless reframed (the "
                    + "clip's zoom, a punch-in) or covered",
                facts: ["size": .string(size)]))
        }
        previous = framing.map { (media.id, $0) }
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

// MARK: Voiceover lines and graphics

extension PlanCut {
    /// Per line: where it plays, its take and how well the take says the text; per graphic: its span, layer and
    /// media (`short` when the movie ends before the span); a line without a take, a graphic without media and,
    /// in an edit without clips, stretches of Main with no picture.
    public static func lineAndGraphicFacts(
        _ spec: Spec, takes: [String: LineTake], placements: [Placement], on project: Project
    ) -> (lines: [JSONValue], graphics: [JSONValue], problems: [Problem]) {
        let fps = project.fps.value
        var problems: [Problem] = []
        let lines = spec.voiceover.map { line -> JSONValue in
            var row: [String: JSONValue] = ["id": .string(line.id)]
            if let section = line.section { row["section"] = .string(section) }
            if let placed = placements.first(where: { $0.id == line.id }) {
                row["at"] = rounded(Double(placed.at) / fps)
                row["seconds"] = rounded(Double(placed.end - placed.at) / fps)
            }
            if let take = takes[line.id] {
                row["take"] = take.media.fields["path"] ?? .null
                for (key, value) in take.facts { row[key] = value }
            } else {
                problems.append(Problem(
                    id: "no-take", severity: "error", entry: line.id,
                    detail: "No kept take says this line: voice lines makes takes for plan.cut.voiceover (or give take, "
                        + "a path voice speak kept)", facts: ["text": .string(line.text)]))
            }
            return .object(row)
        }
        let graphics = spec.graphics.map { graphicRow($0, placements: placements, on: project, problems: &problems) }
        if spec.clips.isEmpty, let main = project.track(role: TrackRole.main) {
            let gaps = pictureGaps(main, length: project.duration)
            if !gaps.isEmpty {
                problems.append(Problem(
                    id: "picture-gap", severity: "warning", entry: nil,
                    detail: "Main shows nothing (black) in \(gaps.count) stretch(es): cover them with graphics on track main",
                    facts: ["gaps": .array(gaps.map { .object(["at": rounded(Double($0.lowerBound) / fps),
                                                              "end": rounded(Double($0.upperBound) / fps)]) })]))
            }
        }
        return (lines, graphics, problems)
    }

    /// The review errors of the edit as it would be built, as one problem, so a check that reads only `problems` sees
    /// them before rendering and building (captions under a platform's caption bar, a cut inside a word…).
    public static func reviewErrorsProblem(_ review: [ReviewIssue]) -> Problem? {
        let errors = review.filter { $0.severity == .error }
        guard let first = errors.first else { return nil }
        var kinds: [String: Int] = [:]
        for issue in errors { kinds[issue.kind, default: 0] += 1 }
        let counts = kinds.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
        return Problem(
            id: "review-errors", severity: "warning", entry: nil,
            detail: "The edit as built has \(errors.count) review error(s) (\(counts)); the first: \(first.title): "
                + "\(first.detail) Fix them in this list before building (review holds each one).",
            facts: ["kinds": .object(kinds.mapValues { .integer($0) }), "first": first.json])
    }

    /// A project without a content language (captions, speech-rate units, voices and font checks read it), with the
    /// language its footage was heard in as the fix.
    public static func languageProblem(_ contentLanguage: String, heard: [String]) -> Problem? {
        guard contentLanguage.isEmpty else { return nil }
        let languages = Array(Set(heard.filter { !$0.isEmpty })).sorted()
        let fix = languages.count == 1 ? "project format --language \(languages[0]) --base-rev last (the footage was heard in "
            + "\(languages[0]))" : "project format --language <tag> --base-rev last"
        return Problem(
            id: "content-language-unset", severity: "warning", entry: nil,
            detail: "The project has no content language, which captions, voices and font checks use: \(fix)",
            facts: ["heard": .array(languages.map(JSONValue.string))])
    }

    /// A graphic's span, layer and media, and what is wrong with it.
    static func graphicRow(
        _ graphic: Graphic, placements: [Placement], on project: Project, problems: inout [Problem]
    ) -> JSONValue {
        let fps = project.fps.value
        var row: [String: JSONValue] = ["id": .string(graphic.id), "track": .string(graphic.main ? "main" : "overlay")]
        if let media = graphic.media { row["media"] = .string(media) }
        guard let placed = placements.first(where: { $0.id == graphic.id }) else {
            problems.append(Problem(
                id: "graphic-unplaced", severity: "error", entry: graphic.id,
                detail: "Its anchor is not placed before it (anchor a graphic only to entries listed earlier) or its span is empty"))
            return .object(row)
        }
        row["at"] = rounded(Double(placed.at) / fps)
        row["seconds"] = rounded(Double(placed.end - placed.at) / fps)
        guard let id = graphic.media else {
            problems.append(Problem(
                id: "graphic-no-media", severity: "error", entry: graphic.id,
                detail: "Give media: the rendered movie's media ID (a graphics plugin's plan command renders the "
                    + "entry's render inputs to this span and fills it in)", facts: ["seconds": row["seconds"] ?? .null]))
            return .object(row)
        }
        guard let media = project.media.first(where: { $0.id == id }) else {
            problems.append(Problem(id: "unknown-media", severity: "error", entry: graphic.id, detail: "No graphic media \(id) in the project"))
            return .object(row)
        }
        if !media.isImage, let asked = placed.asked, asked > placed.end - placed.at + 1 {
            row["short"] = rounded(Double(asked) / fps)
            problems.append(Problem(
                id: "graphic-short", severity: "warning", entry: graphic.id,
                detail: String(format: "The movie ends %.2f s into a %.2f s span: render it longer or shorten the span",
                               Double(placed.end - placed.at) / fps, Double(asked) / fps)))
        }
        return .object(row)
    }

    /// Stretches of `[0, length)` no item of `track` covers.
    static func pictureGaps(_ track: Track, length: Int) -> [Range<Int>] {
        var gaps: [Range<Int>] = []
        var cursor = 0
        for item in track.items.sorted(by: { $0.at < $1.at }) {
            if item.at > cursor { gaps.append(cursor..<min(item.at, length)) }
            cursor = max(cursor, item.end)
            if cursor >= length { break }
        }
        if cursor < length { gaps.append(cursor..<length) }
        return gaps.filter { !$0.isEmpty }
    }
}
