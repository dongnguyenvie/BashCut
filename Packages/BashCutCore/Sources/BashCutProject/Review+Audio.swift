import Foundation

/// Sound checks (#431): measured loudness against the targets, music under speech, dead air and a music bed that
/// drops out.
extension TimelineReview {
    static func audioIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        let audible = project.tracks.filter { $0.kind == "audio" && $0["muted"] != .bool(true) }
        guard audible.contains(where: { !$0.items.isEmpty }) else { return [] }
        return loudnessIssues(project, context: context) + duckingIssues(project, audible: audible)
            + silenceIssues(project, audible: audible, context: context) + musicDropouts(project, audible: audible)
    }

    static func loudnessIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        let targets = context.targets
        guard let target = targets.integratedLUFS else { return [] }
        let normalize = ReviewFix(
            command: "export.start", arguments: targets.measureArguments.merging(["normalizeAudio": .bool(true)]) { $1 },
            hint: "A normalized export measures the mix and sets its gain to the target.")
        guard let loudness = context.loudness, loudness.revision == project.revision else {
            return [
                ReviewIssue(
                    id: "loudness-unmeasured", title: "Loudness not measured",
                    detail: String(
                        format: "This revision has not been measured. Export with audio normalization to reach %.0f LUFS.",
                        target), frame: 0, severity: .info, fix: normalize)
            ]
        }
        var issues: [ReviewIssue] = []
        if abs(loudness.integratedLUFS - target) > targets.toleranceLU {
            issues.append(
                ReviewIssue(
                    id: "loudness", title: "Loudness off target",
                    detail: String(
                        format: "%.1f LUFS; the target is %.0f ±%.0f LU.", loudness.integratedLUFS, target,
                        targets.toleranceLU), frame: 0, severity: .error, fix: normalize))
        }
        if loudness.truePeakDbTP > targets.maxTruePeakDbTP {
            issues.append(
                ReviewIssue(
                    id: "true-peak", title: "True peak too high",
                    detail: String(
                        format: "%.1f dBTP; keep peaks at or below %.0f dBTP so platforms do not clip them.",
                        loudness.truePeakDbTP, targets.maxTruePeakDbTP), frame: 0, severity: .error, fix: normalize))
        }
        return issues
    }

    /// A Music layer with ducking switched off under speech or voiceover.
    static func duckingIssues(_ project: Project, audible: [Track]) -> [ReviewIssue] {
        let speech = speechRegions(project)
        return audible.filter { $0.role == TrackRole.music && $0["duckingEnabled"] == .bool(false) }.compactMap { track in
            guard let item = track.items.sorted(by: { $0.at < $1.at }).first(where: { music in
                speech.contains { music.at < $0.end && music.end > $0.at }
            }) else { return nil }
            let op: JSONValue = .object([
                "op": .string("setTrackProperties"), "track": .string(track.id),
                "patch": .object(["duckingEnabled": .bool(true)]),
            ])
            return ReviewIssue(
                id: "ducking-" + track.id, title: "Music not ducked under speech",
                detail: "Ducking is off on \(track.name.isEmpty ? track.id : track.name) while speech plays over it.",
                frame: item.at,
                fix: ReviewFix(
                    command: "timeline.apply",
                    arguments: ["label": .string("Duck music under speech"), "ops": .array([op])]))
        }
    }

    /// Stretches inside the edit where no audible layer plays, longer than `maxSilenceSeconds`.
    static func silenceIssues(_ project: Project, audible: [Track], context: ReviewContext) -> [ReviewIssue] {
        let limit = Int((context.targets.maxSilenceSeconds * project.fps.value).rounded(.up))
        return gaps(in: audible.flatMap(\.items), from: 0, to: project.duration).filter { $0.end - $0.start > limit }
            .map { gap in
                ReviewIssue(
                    id: "silence-\(gap.start)", title: "Dead air",
                    detail: String(
                        format: "%.1f s with no sound at all. Extend the music bed, add room tone or close the gap.",
                        Double(gap.end - gap.start) / project.fps.value), frame: gap.start,
                    fix: ReviewFix(hint: "Place music or room tone under the gap (library place, media place)."))
            }
    }

    /// A Music layer that stops and starts again for more than a second between its first and last item.
    static func musicDropouts(_ project: Project, audible: [Track]) -> [ReviewIssue] {
        let music = audible.filter { $0.role == TrackRole.music }.flatMap(\.items)
        guard let first = music.map(\.at).min(), let last = music.map(\.end).max() else { return [] }
        let limit = Int(project.fps.value.rounded(.up))
        return gaps(in: music, from: first, to: last).filter { $0.end - $0.start > limit }.map { gap in
            ReviewIssue(
                id: "music-gap-\(gap.start)", title: "Music drops out",
                detail: String(
                    format: "The music stops for %.1f s and comes back. Loop or extend the bed, or fade it out on purpose.",
                    Double(gap.end - gap.start) / project.fps.value), frame: gap.start,
                fix: ReviewFix(hint: "Extend the music item or add the next one at its end."))
        }
    }

    static func speechRegions(_ project: Project) -> [Item] {
        project.tracks.filter { $0.role == TrackRole.voiceover }.flatMap(\.items)
            + project.tracks.filter { $0.role != TrackRole.voiceover }.flatMap(\.items)
            .filter { $0["tag"]?.object["role"]?.string == "speech" }
    }

    /// Frame ranges between `start` and `end` that no item covers.
    static func gaps(in items: [Item], from start: Int, to end: Int) -> [(start: Int, end: Int)] {
        var result: [(start: Int, end: Int)] = []
        var covered = start
        for item in items.sorted(by: { $0.at < $1.at }) where item.end > covered {
            if item.at > covered { result.append((covered, min(item.at, end))) }
            covered = max(covered, item.end)
            if covered >= end { break }
        }
        if covered < end { result.append((covered, end)) }
        return result.filter { $0.end > $0.start }
    }
}
