import Foundation

/// Picture checks (#432): shot length against the pacing range from the timeline, and, from a picture measurement of
/// this revision (`review.measure`), black or empty picture, frozen picture and jump cuts.
extension TimelineReview {
    static func pictureIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        guard project.duration > 0 else { return [] }
        let measured = context.picture.flatMap { $0.revision == project.revision ? $0 : nil }
        var issues: [ReviewIssue] = []
        if measured == nil, context.targets.measuresPicture {
            issues.append(
                ReviewIssue(
                    id: "picture-unmeasured", title: "Picture not measured",
                    detail: "Black frames, frozen picture, jump cuts and plugin checks run on review.measure of this revision.",
                    frame: 0, severity: .info,
                    fix: ReviewFix(command: "review.measure", hint: "Measure, then run the review again.")))
        }
        let profile = ReviewProfile(project)
        issues += shotIssues(project, profile: profile, picture: measured)
        if let measured {
            issues += blackIssues(project, picture: measured, profile: profile)
            issues += stillIssues(project, picture: measured, profile: profile)
            issues += jumpCutIssues(project, picture: measured, profile: profile)
            issues += textContrastIssues(project, picture: measured, profile: profile)
        }
        return issues
    }

    /// Text against the picture behind it, from `review.measure`: under `review.minTextContrast` a warning per item;
    /// without the limit, the lowest measured ratio as info.
    static func textContrastIssues(_ project: Project, picture: ReviewPicture, profile: ReviewProfile) -> [ReviewIssue] {
        let items = Dictionary(project.tracks.flatMap(\.items).map { ($0.id, $0) }) { first, _ in first }
        let measured = picture.textContrast.filter { items[$0.key] != nil }.sorted { $0.value.ratio < $1.value.ratio }
        let ratio = { (value: Double) in String(format: "%.2f:1", value) }
        guard let minimum = profile["minTextContrast"] else {
            guard let lowest = measured.first, let item = items[lowest.key] else { return [] }
            return [
                ReviewIssue(
                    id: "text-contrast", title: "Lowest text contrast \(ratio(lowest.value.ratio))",
                    detail: "\"\(item.text.prefix(40))\" measured against the picture behind it; set "
                        + "review.minTextContrast to judge it.", frame: lowest.value.frame, severity: .info,
                    facts: ["item": .string(lowest.key), "ratio": fact(lowest.value.ratio)])
            ]
        }
        return measured.filter { $0.value.ratio < minimum }.compactMap { id, value in
            guard let item = items[id] else { return nil }
            return ReviewIssue(
                id: "text-contrast-" + id, title: "Text hard to read on its picture",
                detail: "\"\(item.text.prefix(40))\" has contrast \(ratio(value.ratio)) against the picture behind it; "
                    + "the project's minimum is \(ratio(minimum)) (review.minTextContrast).",
                frame: value.frame,
                fix: ReviewFix(hint: "Add a background or a stroke of several points, or move the text to a calmer part."),
                facts: ["ratio": fact(value.ratio), "minTextContrast": .number(minimum)])
        }
    }

    /// Shots on Main against the project's `minShotSeconds`/`maxShotSeconds` (nothing without them). With
    /// `stillMotion`, a long shot is a warning only when its picture moves less; without it, or without a measurement,
    /// long shots are info.
    static func shotIssues(_ project: Project, profile: ReviewProfile, picture: ReviewPicture?) -> [ReviewIssue] {
        let fps = project.fps.value
        let main = project.tracks.first { $0.role == "main" }?.items.sorted { $0.at < $1.at } ?? []
        let seconds = { (shot: Item) in Double(shot.duration) / fps }
        var issues: [ReviewIssue] = []
        if let minimum = profile["minShotSeconds"] {
            issues += main.filter { seconds($0) < minimum }.map { shot in
                ReviewIssue(
                    id: "shot-short-" + shot.id, title: "Very short shot",
                    detail: String(format: "%.2f s; the project's shortest is %.2f s.", seconds(shot), minimum),
                    frame: shot.at, endFrame: shot.end, severity: .info,
                    facts: ["seconds": fact(seconds(shot)), "minimum": .number(minimum)])
            }
        }
        guard let maximum = profile["maxShotSeconds"] else { return issues }
        for shot in main where seconds(shot) > maximum {
            let motion = picture.flatMap { meanChange($0, from: shot.at, to: shot.end) }
            if let still = profile["stillMotion"], let motion, motion >= still { continue }
            var facts: [String: JSONValue] = ["seconds": fact(seconds(shot)), "maximum": .number(maximum)]
            if let motion { facts["meanChange"] = fact(motion) }
            issues.append(
                ReviewIssue(
                    id: "shot-long-" + shot.id, title: "Long shot",
                    detail: String(format: "%.1f s", seconds(shot))
                        + (motion.map { String(format: ", mean picture change %.3f", $0) } ?? " (picture not measured)")
                        + String(format: "; the project's longest is %.0f s.", maximum),
                    frame: shot.at, endFrame: shot.end,
                    severity: profile["stillMotion"] != nil && motion != nil ? .warning : .info, facts: facts))
        }
        return issues
    }

    /// Runs of black, flat picture: inside the edit an error (longer than `review.blackMinSeconds` when set); at its
    /// very start or end, where fades go, info.
    static func blackIssues(_ project: Project, picture: ReviewPicture, profile: ReviewProfile) -> [ReviewIssue] {
        let fps = project.fps.value
        return runs(picture, where: picture.isBlack).compactMap { start, end in
            let seconds = Double(end - start) / fps
            if let minimum = profile["blackMinSeconds"], seconds < minimum { return nil }
            let edge = start == 0 || end >= project.duration
            return ReviewIssue(
                id: "black-" + anchor(project, frame: start), title: edge ? "Black at the edge of the edit" : "Black picture",
                detail: String(format: "%.1f s of black or empty picture from frame %d.", seconds, start),
                frame: start, endFrame: end, severity: edge ? .info : .error,
                facts: ["seconds": fact(seconds), "edge": .bool(edge)])
        }
    }

    /// Unchanged picture outside freeze frames placed on purpose: each run longer than `review.maxStillSeconds`
    /// (warning); nothing without it.
    static func stillIssues(_ project: Project, picture: ReviewPicture, profile: ReviewProfile) -> [ReviewIssue] {
        guard let limit = profile["maxStillSeconds"] else { return [] }
        let fps = project.fps.value
        let freezes = project.tracks.filter { $0.role == "main" }.flatMap(\.items).filter { $0["freezeFrame"] != nil }
        let samples = picture.samples
        // A run of unchanged samples starts at the sample before its first one: that is the picture they repeat.
        let still: [(Int, Int)] = runs(picture) { $0.isStill && !picture.isBlack($0) }.map { first, end in
            let index = samples.firstIndex { $0.frame == first } ?? 0
            return (index > 0 ? samples[index - 1].frame : first, end)
        }.filter { start, end in !freezes.contains(where: { $0.at <= start && $0.end >= end }) }
        return still.filter { Double($0.1 - $0.0) / fps > limit }.map { start, end in
            let seconds = Double(end - start) / fps
            return ReviewIssue(
                id: "still-" + anchor(project, frame: start), title: "Frozen picture",
                detail: String(format: "%.1f s without any change; the project's limit is %.0f s.", seconds, limit),
                frame: start, endFrame: end, severity: .warning,
                facts: ["seconds": fact(seconds), "maximum": .number(limit)])
        }
    }

    /// Hard cuts whose two sides differ less than the project's `review.jumpCutChange` (not checked without it),
    /// including cuts between the same source and transform. How far to reframe, or whether to cut away instead, is
    /// the agent's choice (#468).
    static func jumpCutIssues(_ project: Project, picture: ReviewPicture, profile: ReviewProfile) -> [ReviewIssue] {
        guard let limit = profile["jumpCutChange"] else { return [] }
        let items = Dictionary(project.tracks.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let main = project.tracks.first { $0.role == TrackRole.main }?.items ?? []
        return ReviewPicture.hardCuts(project).compactMap { cut in
            guard let change = picture.cuts[cut.item], change < limit, let right = items[cut.item] else { return nil }
            // Two framings of one picture (a punch-in, another part of a dark screen) are a new shot that a flat
            // picture measures as little change (B7): info, not a jump cut.
            if let left = main.first(where: { $0.end == right.at }), left.mediaID == right.mediaID,
                reframed(left, right, width: Double(project.width))
            {
                return ReviewIssue(
                    id: "jump-" + right.id, title: "Cut between two framings of one picture",
                    detail: String(
                        format: "The picture changes only %.0f%% across this cut, but the two sides are framed "
                            + "differently (zoom, pan, crop or keyframes), so it reads as a new shot.", change * 100),
                    frame: right.at, severity: .info,
                    facts: ["change": fact(change), "minimum": .number(limit), "reframed": .bool(true)])
            }
            return ReviewIssue(
                id: "jump-" + right.id, title: "Jump cut",
                detail: String(format: "The picture changes only %.0f%% across this cut.", change * 100),
                frame: right.at, facts: ["change": fact(change), "minimum": .number(limit)])
        }
    }

    /// Whether two sides of a cut frame the picture differently enough to read as another shot: a zoom 10% apart,
    /// a pan or tilt a tenth of the width apart, another crop, or framing keyframes on either side.
    static func reframed(_ left: Item, _ right: Item, width: Double) -> Bool {
        let framing = { (item: Item) -> (zoom: Double, pan: Double, tilt: Double) in
            let transform = item["transform"]?.object ?? [:]
            return (transform["zoom"]?.double ?? 1, transform["pan"]?.double ?? 0, transform["tilt"]?.double ?? 0)
        }
        let first = framing(left), second = framing(right)
        let zoom = max(first.zoom, second.zoom) / max(0.01, min(first.zoom, second.zoom))
        let moved = max(abs(first.pan - second.pan), abs(first.tilt - second.tilt)) / max(1, width)
        let keyed = [left, right].contains { item in
            item["keyframes"]?.object.keys.contains { ["zoom", "pan", "tilt"].contains($0) } == true
        }
        return zoom >= 1.1 || moved >= 0.1 || left["crop"] != right["crop"] || keyed
    }

    /// Mean sample change inside `from..<to`, nil without samples there.
    static func meanChange(_ picture: ReviewPicture, from: Int, to: Int) -> Double? {
        // The first sample of a shot compares across the cut; leave it out.
        let inside = picture.samples.filter { $0.frame > from && $0.frame < to }
        guard !inside.isEmpty else { return nil }
        return inside.map(\.change).reduce(0, +) / Double(inside.count)
    }

    /// Consecutive samples matching `test`, as the first matching sample's frame and the frame after the last one.
    static func runs(_ picture: ReviewPicture, where test: (ReviewPicture.Sample) -> Bool) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        var start: Int?
        for sample in picture.samples {
            if test(sample) {
                if start == nil { start = sample.frame }
            } else if let first = start {
                result.append((first, sample.frame))
                start = nil
            }
        }
        if let first = start, let last = picture.samples.last { result.append((first, last.frame + picture.interval)) }
        return result
    }
}
