import Foundation

/// Text layout checks (#433) and the hook check (#434).
///
/// Text boxes come from the renderer's layout (`ReviewContext.textLayout`, #465) when the app passes it. Otherwise they
/// are estimated the way `TextRenderer` lays text out: the font is the preset (or `textStyle.size`) share of the
/// frame's short side, shrunk so the widest line fits 90 % of the width; the last line's baseline sits at `positionY`
/// from the bottom and lines stack upwards 1.28 em apart, with glyph widths at 0.55 em per character. The side-zone
/// check stays a warning. Keyframed text motion is not followed for position; for size, keyed `zoom` and
/// `textStyle.size` scale the measured line by the smallest scale the text holds for half a second (`keyedScale`,
/// #521). The zones come from the project's output platforms (`ReviewTargets.layoutPlatform`, #441, #469); text size
/// and caption lines from its `review` profile (#466).
extension TimelineReview {
    struct TextBox {
        let item: Item
        let lines: Int
        /// Font size in pixels after fitting the width.
        let points: Double
        let minX, maxX, minY, maxY: Double
        /// Whether the box is the renderer's layout rather than an estimate.
        var measured = false
        /// The smallest line's font size: an emphasised line drawn under 1× (`textStyle.emphasis.scale`, such as a
        /// template's subline) or a line scaled down by `textStyle.lines` is smaller than `points`.
        var smallestPoints: Double {
            let style = item["textStyle"]?.object ?? [:]
            let emphasis = Self.emphasisScale(item, lines: lines)
            let emphasised = Self.emphasisLine(item, lines: lines)
            let scales = (0..<max(1, lines)).map { index in
                TextLineStyles.scale(style, line: index) * (index == emphasised ? emphasis ?? 1 : 1)
            }
            return points * min(1, emphasis ?? 1, scales.min() ?? 1)
        }

        /// The emphasised line's index when `textStyle.emphasis` names one, else nil.
        static func emphasisLine(_ item: Item, lines: Int) -> Int? {
            guard let line = item["textStyle"]?.object["emphasis"]?.object["line"]?.double.map({ Int($0) }) else { return nil }
            return TextLineStyles.index(line, count: lines)
        }

        /// The scale of the emphasised line when one is drawn, as the renderer clamps it (0.3…3).
        static func emphasisScale(_ item: Item, lines: Int) -> Double? {
            guard lines >= 2, let emphasis = item["textStyle"]?.object["emphasis"]?.object,
                let scale = emphasis["scale"]?.double
            else { return nil }
            if let line = emphasis["line"]?.double.map({ Int($0) }) {
                let index = line < 0 ? lines + line : line
                guard (0..<lines).contains(index) else { return nil }
            }
            return min(3, max(0.3, scale))
        }
    }

    /// The smallest line of a text item as a share of the frame's short side, as `review.minTextSize` measures it.
    public static func smallestTextShare(_ item: Item, in project: Project, context: ReviewContext) -> Double? {
        let width = Double(project.width)
        let height = Double(project.height)
        guard width > 0, height > 0, !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let box = textBox(item, width: width, height: height, context: context)
        return box.smallestPoints * keyedScale(item, fps: project.fps.value) / min(width, height)
    }

    /// The smallest scale a text item holds for at least half a second (or its whole length when shorter) through
    /// its keyed `zoom` and `textStyle.size` (against the stored size); 1 without such keys. A pop-in that starts
    /// small and settles does not count, a title keyed down to 40 % does.
    public static func keyedScale(_ item: Item, fps: Double) -> Double {
        guard let json = item["keyframes"], let motion = try? ItemMotion(json: json),
            motion.keys["zoom"] != nil || motion.keys["textStyle.size"] != nil, item.duration > 0
        else { return 1 }
        let stored = item["textStyle"]?.object["size"]?.double
        let samples = (0..<item.duration).map { frame -> Double in
            var scale = motion.value("zoom", at: Double(frame)) ?? 1
            if let stored, stored > 0, let size = motion.value("textStyle.size", at: Double(frame)) { scale *= size / stored }
            return max(0, scale)
        }
        let window = min(samples.count, max(1, Int((fps / 2).rounded())))
        var smallest = Double.infinity
        for start in 0...(samples.count - window) {
            smallest = min(smallest, samples[start..<(start + window)].max() ?? 1)
        }
        return smallest.isFinite ? smallest : 1
    }

    static func textBox(_ item: Item, width: Double, height: Double, context: ReviewContext) -> TextBox {
        if let layout = context.textLayout?(item, width, height) {
            return TextBox(
                item: item, lines: layout.lines, points: layout.points, minX: layout.minX, maxX: layout.maxX,
                minY: layout.minY, maxY: layout.maxY, measured: true)
        }
        let defaults = context.textDefaults(item.textPreset)
        let style = item["textStyle"]?.object ?? [:]
        let lines = item.text.components(separatedBy: "\n")
        var points = min(width, height) * (style["size"]?.double ?? defaults.size)
        let widest = (lines.map(\.count).max() ?? 0)
        if Double(widest) * 0.55 * points > width * 0.9 { points = width * 0.9 / (Double(widest) * 0.55) }
        let textWidth = Double(widest) * 0.55 * points
        let baseline = height * (style["positionY"]?.double ?? defaults.positionY)
        let minX = item.textPreset == "place-card" ? width * 0.1 : (width - textWidth) / 2
        return TextBox(
            item: item, lines: lines.count, points: points, minX: minX, maxX: minX + textWidth,
            minY: baseline - 0.25 * points, maxY: baseline + Double(lines.count - 1) * 1.28 * points + 0.75 * points)
    }

    static func textIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        let width = Double(project.width)
        let height = Double(project.height)
        guard width > 0, height > 0 else { return [] }
        let vertical = height > width
        let profile = ReviewProfile(project)
        let boxes = project.tracks.filter { $0.kind == "text" && $0["hidden"] != .bool(true) }
            .flatMap { track in track.items.map { (track, $0) } }
            .filter { !$0.1.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { (track: $0.0, box: textBox($0.1, width: width, height: height, context: context)) }
        var issues: [ReviewIssue] = []
        // The zones of every output of this shape, the strictest side of each (#441, #469); none set, none assumed.
        guard let platform = context.targets.layoutPlatform(for: project) else {
            if !boxes.isEmpty {
                issues.append(
                    ReviewIssue(
                        id: "platform-none", title: "No output platform set",
                        detail: "Text is not checked against a platform's covered zones until output.presets names one.",
                        frame: 0, severity: .info,
                        fix: ReviewFix(command: "project.format", hint: "Set the outputs with project format --outputs.")))
            }
            return issues + profileTextIssues(boxes, profile: profile, width: width, height: height, fps: project.fps.value)
                + overlappingText(boxes.map(\.box))
        }
        let area = platform.safeArea
        let top = 1 - area.top
        for (_, box) in boxes {
            let item = box.item
            let zone: [String: JSONValue] = [
                // Shares of the frame, y up from the bottom like positionY.
                "box": .array([fact(box.minX / width), fact(box.minY / height), fact(box.maxX / width), fact(box.maxY / height)]),
                "platform": .string(platform.id),
            ]
            if vertical, box.minY < height * area.bottom {
                issues.append(
                    ReviewIssue(
                        id: "safe-bottom-" + item.id, title: "Text under the platform caption bar",
                        detail: "The bottom \(percent(area.bottom)) of a vertical video is covered by the \(platform.title) "
                            + "caption bar.",
                        frame: item.at, severity: .error,
                        facts: zone.merging(["bottom": .number(area.bottom)]) { $1 }))
            } else if vertical, box.maxX > width * (1 - area.sideWidth), box.minY < height * area.sideHeight {
                issues.append(
                    ReviewIssue(
                        id: "safe-side-" + item.id, title: "Text under the side buttons",
                        detail: "The line reaches the right \(percent(area.sideWidth)) of the lower part, where "
                            + "\(platform.title)'s like/comment buttons sit.",
                        frame: item.at,
                        facts: zone.merging(["sideWidth": .number(area.sideWidth), "sideHeight": .number(area.sideHeight)]) { $1 }))
            }
            if vertical, box.maxY > height * top {
                issues.append(
                    ReviewIssue(
                        id: "safe-top-" + item.id, title: "Text under the top bar",
                        detail: "The top \(percent(area.top)) of a vertical video is covered by \(platform.title)'s tabs.",
                        frame: item.at, facts: zone.merging(["top": .number(area.top)]) { $1 }))
            }
            if !vertical, box.minY < height * area.margin || box.maxY > height * (1 - area.margin) {
                issues.append(
                    ReviewIssue(
                        id: "title-safe-" + item.id, title: "Text outside title safe",
                        detail: "Keep text inside the central \(percent(1 - 2 * area.margin)) of the frame.", frame: item.at,
                        facts: zone.merging(["margin": .number(area.margin)]) { $1 }))
            }
        }
        issues += profileTextIssues(boxes, profile: profile, width: width, height: height, fps: project.fps.value)
        issues += overlappingText(boxes.map(\.box))
        return issues
    }

    /// Text size and caption lines against the project's `review.minTextSize` and `review.captionMaxLines`; neither is
    /// checked without them.
    static func profileTextIssues(
        _ boxes: [(track: Track, box: TextBox)], profile: ReviewProfile, width: Double, height: Double, fps: Double
    ) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        for (track, box) in boxes {
            let scale = keyedScale(box.item, fps: fps)
            let share = box.smallestPoints * scale / min(width, height)
            if let minimum = profile["minTextSize"], share < minimum {
                var line = box.smallestPoints < box.points ? "Its emphasised line draws" : "It draws"
                if scale < 1 { line += " (keyed down to \(percent(scale)) for half a second or more)" }
                var facts: [String: JSONValue] = ["share": fact(share), "minTextSize": .number(minimum)]
                if scale < 1 {
                    facts["styleShare"] = fact(box.smallestPoints / min(width, height))
                    facts["keyedScale"] = fact(scale)
                }
                issues.append(
                    ReviewIssue(
                        id: "small-text-" + box.item.id, title: "Text smaller than the project's minimum",
                        detail: "\(line) below \(percent(minimum)) of the frame's short side (review.minTextSize).",
                        frame: box.item.at,
                        fix: ReviewFix(hint: "Shorten the line, raise textStyle.size, the emphasis scale or its keyed zoom."),
                        facts: facts))
            }
            if let lines = profile["captionMaxLines"].map({ Int($0) }), track.role == TrackRole.captions, box.lines > lines {
                issues.append(
                    ReviewIssue(
                        id: "caption-lines-" + box.item.id, title: "Caption over \(lines) line\(lines == 1 ? "" : "s")",
                        detail: "\(box.lines) lines; the project allows \(lines) (review.captionMaxLines).",
                        frame: box.item.at, fix: ReviewFix(hint: "Split it into shorter captions (captions group).")))
            }
        }
        return issues
    }

    /// Two text items on screen at the same time whose boxes overlap; reported once, at the later one.
    static func overlappingText(_ boxes: [TextBox]) -> [ReviewIssue] {
        let sorted = boxes.sorted { $0.item.at < $1.item.at }
        var reported: Set<String> = []
        var issues: [ReviewIssue] = []
        for (index, box) in sorted.enumerated() {
            for other in sorted[(index + 1)...] {
                guard other.item.at < box.item.end else { break }
                guard box.minY < other.maxY, other.minY < box.maxY, box.minX < other.maxX, other.minX < box.maxX,
                    reported.insert(other.item.id).inserted
                else { continue }
                issues.append(
                    ReviewIssue(
                        id: "text-overlap-" + other.item.id, title: "Overlapping text",
                        detail: "This text covers another text item shown at the same time.", frame: other.item.at,
                        severity: .info,
                        fix: ReviewFix(hint: "Move one with textStyle.positionY or shift it in time.")))
            }
        }
        return issues
    }

    /// Text covering more of a face than the project's `review.maxFaceOverlap` allows, from the face boxes stored for
    /// the clips under it (`media.subjects`); not checked without the limit or without stored boxes.
    static func faceIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        guard let limit = ReviewProfile(project)["maxFaceOverlap"], !context.subjects.isEmpty,
            project.width > 0, project.height > 0
        else { return [] }
        let width = Double(project.width), height = Double(project.height)
        var issues: [ReviewIssue] = []
        for track in project.tracks where track.kind == "text" && track["hidden"] != .bool(true) {
            for item in track.items where !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let box = textBox(item, width: width, height: height, context: context)
                let rect = CGRectLike(x: box.minX, y: box.minY, width: box.maxX - box.minX, height: box.maxY - box.minY)
                guard let overlap = FaceOverlap.measure(
                    rect, from: item.at, to: item.end, project: project, subjects: context.subjects),
                    overlap.ratio > limit
                else { continue }
                issues.append(
                    ReviewIssue(
                        id: "text-face-" + item.id, title: "Text over a face",
                        detail: "The text covers \(percent(overlap.ratio)) of a face in \(overlap.item ?? "a clip") "
                            + "(review.maxFaceOverlap \(percent(limit))).",
                        frame: overlap.frame ?? item.at,
                        fix: ReviewFix(hint: "Move the text (textStyle.positionY) or reframe the clip under it."),
                        facts: ["ratio": fact(overlap.ratio), "maxFaceOverlap": .number(limit), "overlap": overlap.json]))
            }
        }
        return issues
    }

    /// "16%" for 0.16.
    static func percent(_ fraction: Double) -> String { String(format: "%g%%", (fraction * 1000).rounded() / 10) }

    /// Only when the project sets a hook window (`review.hookSeconds`, from a recipe or the user): nothing said and no
    /// text on screen inside it. Core sets no window of its own and does not judge what the text says (#467); the
    /// facts behind the check are `review.hook`.
    static func hookIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        guard let hookSeconds = project["review"]?.object["hookSeconds"]?.double, hookSeconds > 0 else { return [] }
        let hook = Int((hookSeconds * project.fps.value).rounded())
        guard project.duration >= hook * 2 else { return [] }
        if speechRegions(project).contains(where: { $0.at < hook }) { return [] }
        let early = project.tracks.filter { $0.kind == "text" && $0["hidden"] != .bool(true) }.flatMap(\.items)
            .filter { $0.at < hook && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard early.isEmpty else { return [] }
        let seconds = String(format: "%g", hookSeconds)
        return [
            ReviewIssue(
                id: "hook", title: "Nothing said or written in the first \(seconds) seconds",
                detail: "The project's hook window (review.hookSeconds) has no speech and no on-screen text. review hook "
                    + "lists what does happen first.", frame: 0,
                fix: ReviewFix(hint: "Read review hook, then open with the moment the plan chose as the hook."))
        ]
    }
}
