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
        }
        return issues
    }

    /// Shots on Main against the project's `minShotSeconds`/`maxShotSeconds`; without them, the shortest and the longest
    /// shot as info. With `stillMotion`, a long shot is a warning only when its picture moves less; without it, or
    /// without a measurement, long shots are info.
    static func shotIssues(_ project: Project, profile: ReviewProfile, picture: ReviewPicture?) -> [ReviewIssue] {
        let fps = project.fps.value
        let main = project.tracks.first { $0.role == "main" }?.items.sorted { $0.at < $1.at } ?? []
        guard !main.isEmpty else { return [] }
        let seconds = { (shot: Item) in Double(shot.duration) / fps }
        let short = profile["minShotSeconds"].map { limit in main.filter { seconds($0) < limit } }
            ?? [main.min { $0.duration < $1.duration }].compactMap { $0 }
        let long = profile["maxShotSeconds"].map { limit in main.filter { seconds($0) > limit } }
            ?? [main.max { $0.duration < $1.duration }].compactMap { $0 }
        var issues: [ReviewIssue] = short.map { shot in
            ReviewIssue(
                id: "shot-short-" + shot.id, title: profile["minShotSeconds"] == nil ? "Shortest shot" : "Very short shot",
                detail: String(format: "%.2f s", seconds(shot))
                    + (profile["minShotSeconds"].map { String(format: "; the project's shortest is %.2f s.", $0) } ?? "."),
                frame: shot.at, endFrame: shot.end, severity: .info,
                fix: ReviewFix(hint: "Lengthen it, remove it, or keep it as a deliberate beat."))
        }
        for shot in long where profile["minShotSeconds"] != nil || !short.contains(where: { $0.id == shot.id }) {
            let motion = picture.flatMap { meanChange($0, from: shot.at, to: shot.end) }
            if let still = profile["stillMotion"], let motion, motion >= still { continue }
            let warn = profile["maxShotSeconds"] != nil && profile["stillMotion"] != nil && motion != nil
            issues.append(
                ReviewIssue(
                    id: "shot-long-" + shot.id, title: profile["maxShotSeconds"] == nil ? "Longest shot" : "Long shot",
                    detail: String(format: "%.1f s", seconds(shot))
                        + (motion.map { String(format: ", mean picture change %.3f", $0) } ?? " (picture not measured)")
                        + (profile["maxShotSeconds"].map { String(format: "; the project's longest is %.0f s.", $0) } ?? "."),
                    frame: shot.at, endFrame: shot.end, severity: warn ? .warning : .info,
                    fix: ReviewFix(hint: "Split it, add a cutaway, animate it, or keep it on purpose.")))
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
                fix: ReviewFix(hint: "Check for an offline or missing clip, a layer hiding the picture, or a gap under it."))
        }
    }

    /// Unchanged picture outside freeze frames placed on purpose: each run longer than `review.maxStillSeconds`
    /// (warning), or without it the longest run as info.
    static func stillIssues(_ project: Project, picture: ReviewPicture, profile: ReviewProfile) -> [ReviewIssue] {
        let fps = project.fps.value
        let freezes = project.tracks.filter { $0.role == "main" }.flatMap(\.items).filter { $0["freezeFrame"] != nil }
        let samples = picture.samples
        // A run of unchanged samples starts at the sample before its first one: that is the picture they repeat.
        let still: [(Int, Int)] = runs(picture) { $0.isStill && !picture.isBlack($0) }.map { first, end in
            let index = samples.firstIndex { $0.frame == first } ?? 0
            return (index > 0 ? samples[index - 1].frame : first, end)
        }.filter { start, end in !freezes.contains(where: { $0.at <= start && $0.end >= end }) }
        let limit = profile["maxStillSeconds"]
        let flagged = limit.map { limit in still.filter { Double($0.1 - $0.0) / fps > limit } }
            ?? [still.max { $0.1 - $0.0 < $1.1 - $1.0 }].compactMap { $0 }
        return flagged.map { start, end in
            ReviewIssue(
                id: "still-" + anchor(project, frame: start), title: limit == nil ? "Longest unchanged picture" : "Frozen picture",
                detail: String(format: "%.1f s without any change", Double(end - start) / fps)
                    + (limit.map { String(format: "; the project's limit is %.0f s.", $0) } ?? "."),
                frame: start, endFrame: end, severity: limit == nil ? .info : .warning,
                fix: ReviewFix(hint: "Animate it, cut sooner, put b-roll over it, or keep it on purpose."))
        }
    }

    /// Hard cuts whose two sides differ less than the project's `review.jumpCutChange` (not checked without it).
    /// Cuts between the same source and transform are already "Repeated framing". The fix is a hint: how far to
    /// reframe, or whether to cut away instead, is the agent's choice (#468).
    static func jumpCutIssues(_ project: Project, picture: ReviewPicture, profile: ReviewProfile) -> [ReviewIssue] {
        guard let limit = profile["jumpCutChange"] else { return [] }
        let items = Dictionary(project.tracks.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let main = project.tracks.first { $0.role == "main" }?.items.sorted { $0.at < $1.at } ?? []
        let previous = Dictionary(zip(main.dropFirst(), main).map { ($0.id, $1) }, uniquingKeysWith: { first, _ in first })
        return ReviewPicture.hardCuts(project).compactMap { cut in
            guard let change = picture.cuts[cut.item], change < limit,
                let right = items[cut.item], let left = previous[cut.item],
                !(left.mediaID == right.mediaID && left["transform"] == right["transform"])
            else { return nil }
            return ReviewIssue(
                id: "jump-" + right.id, title: "Jump cut",
                detail: String(format: "The picture changes only %.0f%% across this cut.", change * 100),
                frame: right.at,
                fix: ReviewFix(hint: "Reframe one side (review shots gives each shot's scale headroom) or put a cutaway between them."))
        }
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
