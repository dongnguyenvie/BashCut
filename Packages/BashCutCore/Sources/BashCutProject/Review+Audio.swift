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
    /// platform fact (error); loudness off by more than `review.loudnessToleranceLU` is an error (not checked
    /// without that limit; `audio.measure` reports the numbers).
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
        if let target = loudness.targetLUFS, let tolerance = profile["loudnessToleranceLU"],
            abs(loudness.integratedLUFS - target) > tolerance
        {
            issues.append(
                ReviewIssue(
                    id: "loudness", title: "Loudness off target",
                    detail: String(format: "%@; the export's target is %.0f ±%.1f LU.", measured, target, tolerance),
                    frame: 0, severity: .error, fix: normalize,
                    facts: ["lufs": fact(loudness.integratedLUFS), "target": .number(target), "tolerance": .number(tolerance)]))
        }
        if let ceiling = loudness.maxTruePeakDbTP, loudness.truePeakDbTP > ceiling {
            issues.append(
                ReviewIssue(
                    id: "true-peak", title: "True peak too high",
                    detail: String(format: "%.1f dBTP over the export's %.0f dBTP ceiling.", loudness.truePeakDbTP, ceiling),
                    frame: 0, severity: .error, fix: normalize,
                    facts: ["truePeak": fact(loudness.truePeakDbTP), "ceiling": .number(ceiling)]))
        }
        return issues
    }

    /// A ducking Music layer that pumps (#630): it rises in gaps between lines shorter than 2.5 s more than 4 times
    /// (down and up) a minute. The fix holds it down in those gaps; a fixed bed (ducking off) is the other way.
    static func duckingIssues(_ project: Project, audible: [Track]) -> [ReviewIssue] {
        let fps = project.fps.value
        let ids = Set(audible.map(\.id))
        return MusicDucking.beds(project).filter { $0.pumping && ids.contains($0.track) }.compactMap { bed in
            guard let track = project.tracks.first(where: { $0.id == bed.track }), let first = bed.shortRises.first else {
                return nil
            }
            let hold = Int((MusicDucking.defaultMinGapSeconds * fps).rounded())
            let op: JSONValue = .object([
                "op": .string("setTrackProperties"), "track": .string(track.id),
                "patch": .object(["duckMinGapFrames": .integer(hold)]),
            ])
            return ReviewIssue(
                id: "music-pumping-" + track.id, title: "Music pumps between lines",
                detail: String(
                    format: "%@ comes back up in %d gaps shorter than %.1f s (%.1f moves a minute); hold it down or "
                        + "set one fixed level with ducking off.",
                    track.name.isEmpty ? track.id : track.name, bed.shortRises.count, MusicDucking.defaultMinGapSeconds,
                    bed.movesPerMinute),
                frame: first.lowerBound, severity: .warning,
                fix: ReviewFix(
                    command: "timeline.apply",
                    arguments: ["label": .string("Hold music down between lines"), "ops": .array([op])]),
                facts: [
                    "shortRises": .integer(bed.shortRises.count), "movesPerMinute": fact(bed.movesPerMinute),
                    "duckMinGapFrames": .integer(bed.minGapFrames),
                ])
        }
    }

    /// Stretches with no audible layer longer than `review.maxSilenceSeconds` (nothing without it).
    static func silenceIssues(_ project: Project, audible: [Track], profile: ReviewProfile) -> [ReviewIssue] {
        guard let limit = profile["maxSilenceSeconds"] else { return [] }
        let fps = project.fps.value
        return gaps(in: audible.flatMap(\.items), from: 0, to: project.duration, over: limit, fps: fps).map { gap in
            let seconds = Double(gap.end - gap.start) / fps
            return ReviewIssue(
                id: "silence-" + anchor(project, frame: gap.start), title: "Dead air",
                detail: String(format: "%.1f s with no sound at all.", seconds),
                frame: gap.start, endFrame: gap.end, facts: ["seconds": fact(seconds), "maximum": .number(limit)])
        }
    }

    /// Gaps inside the music bed longer than `review.maxMusicGapSeconds` (nothing without it).
    static func musicDropouts(_ project: Project, audible: [Track], profile: ReviewProfile) -> [ReviewIssue] {
        guard let limit = profile["maxMusicGapSeconds"] else { return [] }
        let music = audible.filter { $0.role == TrackRole.music }.flatMap(\.items)
        guard let first = music.map(\.at).min(), let last = music.map(\.end).max() else { return [] }
        let fps = project.fps.value
        return gaps(in: music, from: first, to: last, over: limit, fps: fps).map { gap in
            let seconds = Double(gap.end - gap.start) / fps
            return ReviewIssue(
                id: "music-gap-" + anchor(project, frame: gap.start), title: "Music drops out",
                detail: String(format: "The music stops for %.1f s and comes back.", seconds),
                frame: gap.start, endFrame: gap.end, facts: ["seconds": fact(seconds), "maximum": .number(limit)])
        }
    }

    /// The gaps longer than `limit` seconds.
    static func gaps(
        in items: [Item], from start: Int, to end: Int, over limit: Double, fps: Double
    ) -> [(start: Int, end: Int)] {
        let frames = Int((limit * fps).rounded(.up))
        return gaps(in: items, from: start, to: end).filter { $0.end - $0.start > frames }
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
