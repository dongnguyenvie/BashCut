import Foundation

/// Sound checks (#431): measured loudness against the export's target, ducking, dead air and a music bed that drops
/// out, with the project's limits (#466).
extension TimelineReview {
    static func audioIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        let audible = project.tracks.filter { $0.kind == "audio" && $0["muted"] != .bool(true) }
        guard audible.contains(where: { !$0.items.isEmpty }) else { return [] }
        let profile = ReviewProfile(project)
        return loudnessIssues(project, context: context, profile: profile) + duckingIssues(project, audible: audible)
            + silenceIssues(project, audible: audible, profile: profile) + musicDropouts(project, audible: audible, profile: profile)
    }

    /// The last normalized export of this revision against its own target (P0-K2): true peak over the target is a
    /// platform fact (error); loudness off by more than `review.loudnessToleranceLU` is an error, and without that
    /// limit the measurement is reported as info.
    static func loudnessIssues(_ project: Project, context: ReviewContext, profile: ReviewProfile) -> [ReviewIssue] {
        let normalize = ReviewFix(
            command: "export.start",
            arguments: context.targets.measureArguments.merging(["normalizeAudio": .bool(true)]) { $1 },
            hint: "A normalized export measures the mix and sets its gain to that export's target.")
        guard let loudness = context.loudness, loudness.revision == project.revision else {
            return [
                ReviewIssue(
                    id: "loudness-unmeasured", title: "Loudness not measured",
                    detail: "This revision has not been measured; a normalized export measures it.", frame: 0,
                    severity: .info, fix: normalize)
            ]
        }
        var issues: [ReviewIssue] = []
        let measured = String(format: "%.1f LUFS, true peak %.1f dBTP", loudness.integratedLUFS, loudness.truePeakDbTP)
        if let target = loudness.targetLUFS {
            let tolerance = profile["loudnessToleranceLU"]
            let off = abs(loudness.integratedLUFS - target)
            if let tolerance, off > tolerance {
                issues.append(
                    ReviewIssue(
                        id: "loudness", title: "Loudness off target",
                        detail: String(format: "%@; the export's target is %.0f ±%.1f LU.", measured, target, tolerance),
                        frame: 0, severity: .error, fix: normalize))
            } else if tolerance == nil {
                issues.append(
                    ReviewIssue(
                        id: "loudness", title: "Loudness measured",
                        detail: String(format: "%@; the export's target is %.0f LUFS.", measured, target), frame: 0,
                        severity: .info))
            }
        }
        if let ceiling = loudness.maxTruePeakDbTP, loudness.truePeakDbTP > ceiling {
            issues.append(
                ReviewIssue(
                    id: "true-peak", title: "True peak too high",
                    detail: String(format: "%.1f dBTP over the export's %.0f dBTP ceiling.", loudness.truePeakDbTP, ceiling),
                    frame: 0, severity: .error, fix: normalize))
        }
        return issues
    }

    /// A Music layer with ducking switched off under speech or voiceover, as info: ducking is a choice.
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
                frame: item.at, severity: .info,
                fix: ReviewFix(
                    command: "timeline.apply",
                    arguments: ["label": .string("Duck music under speech"), "ops": .array([op])]))
        }
    }

    /// Stretches with no audible layer: each one longer than `review.maxSilenceSeconds`, or without that limit the
    /// longest one as info.
    static func silenceIssues(_ project: Project, audible: [Track], profile: ReviewProfile) -> [ReviewIssue] {
        let found = gaps(in: audible.flatMap(\.items), from: 0, to: project.duration)
        return limited(found, limit: profile["maxSilenceSeconds"], fps: project.fps.value) { gap, limited in
            ReviewIssue(
                id: "silence-" + anchor(project, frame: gap.start), title: limited ? "Dead air" : "Longest stretch without sound",
                detail: String(format: "%.1f s with no sound at all.", Double(gap.end - gap.start) / project.fps.value),
                frame: gap.start, severity: limited ? .warning : .info,
                fix: ReviewFix(hint: "Place music or room tone under the gap, close it, or keep the silence on purpose."))
        }
    }

    /// Gaps inside the music bed: each one longer than `review.maxMusicGapSeconds`, or without that limit the longest
    /// one as info.
    static func musicDropouts(_ project: Project, audible: [Track], profile: ReviewProfile) -> [ReviewIssue] {
        let music = audible.filter { $0.role == TrackRole.music }.flatMap(\.items)
        guard let first = music.map(\.at).min(), let last = music.map(\.end).max() else { return [] }
        let found = gaps(in: music, from: first, to: last)
        return limited(found, limit: profile["maxMusicGapSeconds"], fps: project.fps.value) { gap, limited in
            ReviewIssue(
                id: "music-gap-" + anchor(project, frame: gap.start), title: limited ? "Music drops out" : "Longest gap in the music",
                detail: String(
                    format: "The music stops for %.1f s and comes back.", Double(gap.end - gap.start) / project.fps.value),
                frame: gap.start, severity: limited ? .warning : .info,
                fix: ReviewFix(hint: "Extend the music item, add the next one at its end, or keep the pause on purpose."))
        }
    }

    /// Gaps over `limit` seconds, or without a limit only the longest gap.
    static func limited(
        _ gaps: [(start: Int, end: Int)], limit: Double?, fps: Double,
        issue: ((start: Int, end: Int), Bool) -> ReviewIssue
    ) -> [ReviewIssue] {
        guard let limit else {
            return gaps.max { $0.end - $0.start < $1.end - $1.start }.map { [issue($0, false)] } ?? []
        }
        let frames = Int((limit * fps).rounded(.up))
        return gaps.filter { $0.end - $0.start > frames }.map { issue($0, true) }
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
