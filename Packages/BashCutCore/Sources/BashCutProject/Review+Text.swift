import Foundation

/// Text layout checks (#433) and the hook check (#434).
///
/// Text boxes are estimated the way `TextRenderer` lays text out: the font is the preset (or `textStyle.size`) share
/// of the frame's short side, shrunk so the widest line fits 90 % of the width; the last line's baseline sits at
/// `positionY` from the bottom and lines stack upwards 1.28 em apart. Glyph widths are estimated (0.55 em per
/// character), so the side-zone check is a warning, not an error. Keyframed text motion is not followed.
extension TimelineReview {
    /// The platform UI zones on a vertical frame, as fractions: TikTok, Reels and Shorts cover the bottom 16 % with
    /// the caption bar, the right 14 % of the lower 46 % with buttons, and the top 8 % with tabs. Same zones as the
    /// viewer's safe-area overlay.
    enum VerticalSafeArea {
        static let bottom = 0.16
        static let sideWidth = 0.14
        static let sideHeight = 0.46
        static let top = 0.92
    }

    /// Landscape and square frames keep text inside the central 90 % (title safe).
    static let titleSafeMargin = 0.05
    /// Smallest readable text, as a share of the frame's short side (about 32 px on 1080).
    static let minimumTextSize = 0.03

    struct TextBox {
        let item: Item
        let lines: Int
        /// Font size in pixels after fitting the width.
        let points: Double
        let minX, maxX, minY, maxY: Double
    }

    static func textBox(_ item: Item, width: Double, height: Double, context: ReviewContext) -> TextBox {
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
        let boxes = project.tracks.filter { $0.kind == "text" && $0["hidden"] != .bool(true) }
            .flatMap { track in track.items.map { (track, $0) } }
            .filter { !$0.1.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { (track: $0.0, box: textBox($0.1, width: width, height: height, context: context)) }
        var issues: [ReviewIssue] = []
        for (track, box) in boxes {
            let item = box.item
            if vertical, box.minY < height * VerticalSafeArea.bottom {
                let raised = VerticalSafeArea.bottom + 0.25 * box.points / height + 0.02
                issues.append(
                    ReviewIssue(
                        id: "safe-bottom-" + item.id, title: "Text under the platform caption bar",
                        detail: "The bottom 16% of a vertical video is covered by the TikTok/Reels/Shorts caption bar.",
                        frame: item.at, severity: .error, fix: moveText(item, positionY: raised)))
            } else if vertical, box.maxX > width * (1 - VerticalSafeArea.sideWidth),
                box.minY < height * VerticalSafeArea.sideHeight
            {
                issues.append(
                    ReviewIssue(
                        id: "safe-side-" + item.id, title: "Text under the side buttons",
                        detail: "The line reaches the right 14% of the lower half, where the like/comment buttons sit. "
                            + "Use shorter lines (3–6 words) or a smaller size.",
                        frame: item.at, fix: ReviewFix(hint: "Split the line or lower textStyle.size.")))
            }
            if vertical, box.maxY > height * VerticalSafeArea.top {
                issues.append(
                    ReviewIssue(
                        id: "safe-top-" + item.id, title: "Text under the top bar",
                        detail: "The top 8% of a vertical video is covered by the app's tabs.", frame: item.at,
                        fix: moveText(item, positionY: max(0, (height * VerticalSafeArea.top - (box.maxY - box.minY)) / height - 0.02))))
            }
            if !vertical, box.minY < height * titleSafeMargin || box.maxY > height * (1 - titleSafeMargin) {
                issues.append(
                    ReviewIssue(
                        id: "title-safe-" + item.id, title: "Text outside title safe",
                        detail: "Keep text inside the central 90% of the frame.", frame: item.at,
                        fix: ReviewFix(hint: "Move it with textStyle.positionY.")))
            }
            if box.points / min(width, height) < minimumTextSize {
                issues.append(
                    ReviewIssue(
                        id: "small-text-" + item.id, title: "Text too small",
                        detail: "It draws below 3% of the frame's short side and is hard to read on a phone. "
                            + "Shorten the line or raise textStyle.size.", frame: item.at))
            }
            if vertical, track.role == TrackRole.captions, box.lines > 2 {
                issues.append(
                    ReviewIssue(
                        id: "caption-lines-" + item.id, title: "Caption over two lines",
                        detail: "Vertical captions read best as one short line (3–6 words), two at most.",
                        frame: item.at, fix: ReviewFix(hint: "Split it into shorter captions.")))
            }
        }
        issues += overlappingText(boxes.map(\.box))
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

    /// `timeline.apply` that sets `textStyle.positionY`, keeping the item's other style fields.
    static func moveText(_ item: Item, positionY: Double) -> ReviewFix {
        var style = item["textStyle"]?.object ?? [:]
        style["positionY"] = .number((min(0.9, max(0, positionY)) * 1000).rounded() / 1000)
        let op: JSONValue = .object([
            "op": .string("setProperties"), "item": .string(item.id), "patch": .object(["textStyle": .object(style)]),
        ])
        return ReviewFix(command: "timeline.apply", arguments: ["label": .string("Move text into the safe area"), "ops": .array([op])])
    }

    /// The edit should hook in its first seconds: on-screen text with a number or a question, or speech right away.
    /// Every Reelcrew/AgentVid reference opens with a question and a concrete number in 1–3 s.
    static func hookIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        let fps = project.fps.value
        let hook = Int((context.targets.hookSeconds * fps).rounded())
        guard project.duration >= hook * 2 else { return [] }
        if speechRegions(project).contains(where: { $0.at <= Int((0.5 * fps).rounded()) }) { return [] }
        let early = project.tracks.filter { $0.kind == "text" && $0["hidden"] != .bool(true) }.flatMap(\.items)
            .filter { $0.at < hook && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if early.contains(where: { $0.text.contains("?") || $0.text.contains(where: \.isNumber) }) { return [] }
        let seconds = String(format: "%.0f", context.targets.hookSeconds)
        if let first = early.min(by: { $0.at < $1.at }) {
            return [
                ReviewIssue(
                    id: "hook", title: "Hook without a number or question",
                    detail: "The opening text has neither. A question or a concrete number (price, time, count) holds viewers better.",
                    frame: first.at, severity: .info)
            ]
        }
        return [
            ReviewIssue(
                id: "hook", title: "No hook in the first \(seconds) seconds",
                detail: "No on-screen text and no speech in the first \(seconds) s. Open with a title card: a question or a "
                    + "concrete number (hook-title preset).", frame: 0,
                fix: ReviewFix(hint: "Add a hook-title text item at frame 0."))
        ]
    }
}
