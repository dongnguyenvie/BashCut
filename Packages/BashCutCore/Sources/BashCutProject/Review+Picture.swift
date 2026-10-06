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
        issues += shotIssues(project, context: context, picture: measured)
        if let measured {
            issues += blackIssues(project, picture: measured)
            issues += stillIssues(project, context: context, picture: measured)
            issues += jumpCutIssues(project, picture: measured)
        }
        return issues
    }

    /// Shots on Main outside the pacing range. A long shot is a warning when its picture barely moves (or was not
    /// measured, as a note); a long shot that keeps moving, such as an animated explainer, passes.
    static func shotIssues(_ project: Project, context: ReviewContext, picture: ReviewPicture?) -> [ReviewIssue] {
        let pacing = context.targets.pacing(for: project)
        let fps = project.fps.value
        let main = project.tracks.first { $0.role == "main" }?.items.sorted { $0.at < $1.at } ?? []
        var issues: [ReviewIssue] = []
        for shot in main {
            let seconds = Double(shot.duration) / fps
            if seconds < pacing.minShot {
                issues.append(
                    ReviewIssue(
                        id: "shot-short-" + shot.id, title: "Very short shot",
                        detail: String(format: "%.2f s; shots under %.1f s read as a flash.", seconds, pacing.minShot),
                        frame: shot.at, endFrame: shot.end, severity: .info,
                        fix: ReviewFix(hint: "Lengthen it, remove it, or make it a deliberate beat cut.")))
            } else if seconds > pacing.maxShot {
                let motion = picture.flatMap { meanChange($0, from: shot.at, to: shot.end) }
                guard motion.map({ $0 < 0.02 }) ?? true else { continue }
                issues.append(
                    ReviewIssue(
                        id: "shot-long-" + shot.id, title: motion == nil ? "Long shot" : "Long static shot",
                        detail: String(
                            format: "%.1f s; the pacing range ends at %.0f s%@.", seconds, pacing.maxShot,
                            motion == nil ? " (picture not measured)" : " and the picture barely moves"),
                        frame: shot.at, endFrame: shot.end, severity: motion == nil ? .info : .warning,
                        fix: ReviewFix(hint: "Split it with a punch-in, add a cutaway or b-roll, or animate it (Ken Burns).")))
            }
        }
        return issues
    }

    /// Runs of black, flat picture of half a second or more. A fade to black of up to a second at the very end passes.
    static func blackIssues(_ project: Project, picture: ReviewPicture) -> [ReviewIssue] {
        let fps = project.fps.value
        return runs(picture, where: picture.isBlack).compactMap { start, end in
            let seconds = Double(end - start) / fps
            guard seconds >= 0.5, !(end >= project.duration && seconds <= 1) else { return nil }
            return ReviewIssue(
                id: "black-\(start)", title: "Black picture",
                detail: String(format: "%.1f s of black or empty picture from frame %d.", seconds, start),
                frame: start, endFrame: end, severity: .error,
                fix: ReviewFix(hint: "Check for an offline or missing clip, a layer hiding the picture, or a gap under it."))
        }
    }

    /// Picture that stays the same for longer than the pacing allows, outside freeze frames placed on purpose.
    static func stillIssues(_ project: Project, context: ReviewContext, picture: ReviewPicture) -> [ReviewIssue] {
        let maxStill = context.targets.pacing(for: project).maxStill
        let fps = project.fps.value
        let freezes = project.tracks.filter { $0.role == "main" }.flatMap(\.items).filter { $0["freezeFrame"] != nil }
        let samples = picture.samples
        // A run of unchanged samples starts at the sample before its first one: that is the picture they repeat.
        let still = runs(picture) { sample in
            sample.change < ReviewPicture.stillChange && !picture.isBlack(sample)
        }
        return still.compactMap { first, end in
            let index = samples.firstIndex { $0.frame == first } ?? 0
            let start = index > 0 ? samples[index - 1].frame : first
            let seconds = Double(end - start) / fps
            guard seconds > maxStill, !freezes.contains(where: { $0.at <= start && $0.end >= end }) else { return nil }
            return ReviewIssue(
                id: "still-\(start)", title: "Frozen picture",
                detail: String(format: "%.1f s without any change; keep still picture under %.0f s.", seconds, maxStill),
                frame: start, endFrame: end,
                fix: ReviewFix(hint: "Animate it (Ken Burns, a slow punch-in), cut sooner, or put b-roll over it."))
        }
    }

    /// Hard cuts whose two sides look nearly the same. Cuts between the same source and transform are already
    /// "Repeated framing"; this finds the rest, such as two takes from a locked-off camera.
    static func jumpCutIssues(_ project: Project, picture: ReviewPicture) -> [ReviewIssue] {
        let items = Dictionary(project.tracks.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let main = project.tracks.first { $0.role == "main" }?.items.sorted { $0.at < $1.at } ?? []
        let previous = Dictionary(zip(main.dropFirst(), main).map { ($0.id, $1) }, uniquingKeysWith: { first, _ in first })
        return ReviewPicture.hardCuts(project).compactMap { cut in
            guard let change = picture.cuts[cut.item], change < ReviewPicture.jumpCutChange,
                  let right = items[cut.item], let left = previous[cut.item],
                  !(left.mediaID == right.mediaID && left["transform"] == right["transform"])
            else { return nil }
            var transform = right["transform"]?.object ?? [:]
            transform["zoom"] = .number((transform["zoom"]?.double ?? 1) * 1.15)
            let op: JSONValue = .object([
                "op": .string("setProperties"), "item": .string(right.id), "patch": .object(["transform": .object(transform)]),
            ])
            return ReviewIssue(
                id: "jump-" + right.id, title: "Jump cut",
                detail: String(format: "The picture changes only %.0f%% across this cut.", change * 100),
                frame: right.at,
                fix: ReviewFix(
                    command: "timeline.apply", arguments: ["ops": .array([op]), "label": .string("Punch in")],
                    hint: "Punch in on one side (zoom 1.15) or put a cutaway between them."))
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
