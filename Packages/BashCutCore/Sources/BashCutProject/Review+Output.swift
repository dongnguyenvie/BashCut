import Foundation

/// Platform checks (#441) and the project's own severities (#439).
extension TimelineReview {
    /// The edit against its output platform: longer than the platform takes, or a frame of another shape (the
    /// export would add bars).
    static func outputIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        guard let platform = context.targets.platform, project.duration > 0 else { return [] }
        var issues: [ReviewIssue] = []
        let seconds = Double(project.duration) / project.fps.value
        if let limit = platform.maxSeconds, seconds > limit {
            issues.append(
                ReviewIssue(
                    id: "output-length", title: "Too long for \(platform.title)",
                    detail: String(
                        format: "The edit runs %@; %@ takes at most %@.", clock(seconds), platform.title, clock(limit)),
                    frame: Int((limit * project.fps.value).rounded()), severity: .error,
                    fix: ReviewFix(hint: "Cut it down, or export a shorter version for this platform.")))
        }
        let vertical = project.height > project.width
        if platform.vertical != vertical || (!vertical && project.width == project.height) {
            issues.append(
                ReviewIssue(
                    id: "output-shape", title: "Frame does not match \(platform.title)",
                    detail: "\(platform.title) is \(platform.vertical ? "vertical (9:16)" : "landscape (16:9)"); the "
                        + "\(project.width) × \(project.height) frame would get bars.", frame: 0,
                    fix: ReviewFix(
                        command: "project.format",
                        arguments: ["canvas": .string(platform.vertical ? "portrait" : "landscape")])))
        }
        return issues
    }

    /// "1:05" for 65 seconds.
    static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// The project's `review.severities` (a recipe sets them): check ID → `error`, `warning`, `info` or `off`. A key
    /// matches an issue whose ID is the key or starts with the key and a hyphen (`safe` covers `safe-bottom-…`);
    /// the longest matching key wins. `off` drops the issue.
    static func applyingSeverities(_ issues: [ReviewIssue], project: Project) -> [ReviewIssue] {
        let overrides = (project["review"]?.object["severities"]?.object ?? [:]).compactMapValues(\.string)
        guard !overrides.isEmpty else { return issues }
        let keys = overrides.keys.sorted { $0.count > $1.count }
        return issues.compactMap { issue in
            guard let key = keys.first(where: { issue.id == $0 || issue.id.hasPrefix($0 + "-") }),
                let value = overrides[key]
            else { return issue }
            guard let severity = ReviewSeverity(rawValue: value) else { return value == "off" ? nil : issue }
            return ReviewIssue(
                id: issue.id, title: issue.title, detail: issue.detail, frame: issue.frame, endFrame: issue.endFrame,
                severity: severity, fix: issue.fix, source: issue.source)
        }
    }
}
