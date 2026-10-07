import Foundation

/// Text layout checks (#433) and the hook check (#434).
///
/// Text boxes come from the renderer's layout (`ReviewContext.textLayout`, #465) when the app passes it. Otherwise they
/// are estimated the way `TextRenderer` lays text out: the font is the preset (or `textStyle.size`) share of the
/// frame's short side, shrunk so the widest line fits 90 % of the width; the last line's baseline sits at `positionY`
/// from the bottom and lines stack upwards 1.28 em apart, with glyph widths at 0.55 em per character. The side-zone
/// check stays a warning. Keyframed text motion is not followed. The zones come from the project's output platforms
/// (`ReviewTargets.layoutPlatform`, #441, #469); text size and caption lines from its `review` profile (#466).
extension TimelineReview {
    struct TextBox {
        let item: Item
        let lines: Int
        /// Font size in pixels after fitting the width.
        let points: Double
        let minX, maxX, minY, maxY: Double
        /// Whether the box is the renderer's layout rather than an estimate.
        var measured = false
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
            return issues + profileTextIssues(boxes, profile: profile, width: width, height: height)
                + overlappingText(boxes.map(\.box))
        }
        let area = platform.safeArea
        let top = 1 - area.top
        for (_, box) in boxes {
            let item = box.item
            if vertical, box.minY < height * area.bottom {
                let raised = area.bottom + 0.25 * box.points / height + 0.02
                issues.append(
                    ReviewIssue(
                        id: "safe-bottom-" + item.id, title: "Text under the platform caption bar",
                        detail: "The bottom \(percent(area.bottom)) of a vertical video is covered by the \(platform.title) "
                            + "caption bar.",
                        frame: item.at, severity: .error, fix: moveText(item, positionY: raised)))
            } else if vertical, box.maxX > width * (1 - area.sideWidth), box.minY < height * area.sideHeight {
                issues.append(
                    ReviewIssue(
                        id: "safe-side-" + item.id, title: "Text under the side buttons",
                        detail: "The line reaches the right \(percent(area.sideWidth)) of the lower part, where "
                            + "\(platform.title)'s like/comment buttons sit.",
                        frame: item.at, fix: ReviewFix(hint: "Shorten or split the line, lower textStyle.size, or move it.")))
            }
            if vertical, box.maxY > height * top {
                issues.append(
                    ReviewIssue(
                        id: "safe-top-" + item.id, title: "Text under the top bar",
                        detail: "The top \(percent(area.top)) of a vertical video is covered by \(platform.title)'s tabs.",
                        frame: item.at,
                        fix: moveText(item, positionY: max(0, (height * top - (box.maxY - box.minY)) / height - 0.02))))
            }
            if !vertical, box.minY < height * area.margin || box.maxY > height * (1 - area.margin) {
                issues.append(
                    ReviewIssue(
                        id: "title-safe-" + item.id, title: "Text outside title safe",
                        detail: "Keep text inside the central \(percent(1 - 2 * area.margin)) of the frame.", frame: item.at,
                        fix: ReviewFix(hint: "Move it with textStyle.positionY.")))
            }
        }
        issues += profileTextIssues(boxes, profile: profile, width: width, height: height)
        issues += overlappingText(boxes.map(\.box))
        return issues
    }

    /// Text size and caption lines against the project's `review.minTextSize` and `review.captionMaxLines`; neither is
    /// checked without them.
    static func profileTextIssues(
        _ boxes: [(track: Track, box: TextBox)], profile: ReviewProfile, width: Double, height: Double
    ) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        for (track, box) in boxes {
            if let minimum = profile["minTextSize"], box.points / min(width, height) < minimum {
                issues.append(
                    ReviewIssue(
                        id: "small-text-" + box.item.id, title: "Text smaller than the project's minimum",
                        detail: "It draws below \(percent(minimum)) of the frame's short side (review.minTextSize).",
                        frame: box.item.at, fix: ReviewFix(hint: "Shorten the line or raise textStyle.size.")))
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
                        fix: ReviewFix(hint: "Move one with textStyle.positionY or shift it in time.")))
            }
        }
        return issues
    }

    /// "16%" for 0.16.
    static func percent(_ fraction: Double) -> String { String(format: "%g%%", (fraction * 1000).rounded() / 10) }

    /// `timeline.apply` that sets `textStyle.positionY`, keeping the item's other style fields.
    static func moveText(_ item: Item, positionY: Double) -> ReviewFix {
        var style = item["textStyle"]?.object ?? [:]
        style["positionY"] = .number((min(0.9, max(0, positionY)) * 1000).rounded() / 1000)
        let op: JSONValue = .object([
            "op": .string("setProperties"), "item": .string(item.id), "patch": .object(["textStyle": .object(style)]),
        ])
        return ReviewFix(command: "timeline.apply", arguments: ["label": .string("Move text into the safe area"), "ops": .array([op])])
    }

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
