import Foundation

/// Platform checks (#441) and the project's own severities (#439).
extension TimelineReview {
    /// The edit against its output platform: longer than the platform takes, or a frame of another shape (the
    /// export would add bars).
    static func outputIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        guard project.duration > 0 else { return [] }
        var issues: [ReviewIssue] = []
        let seconds = Double(project.duration) / project.fps.value
        let profile = ReviewProfile(project)
        var seen = Set<String>()
        for platform in context.targets.platforms.filter({ seen.insert($0.id).inserted }).map(profile.applying) {
            if let limit = platform.maxSeconds, seconds > limit {
                issues.append(
                    ReviewIssue(
                        id: "output-length-" + platform.id, title: "Too long for \(platform.title)",
                        detail: String(
                            format: "The edit runs %@; %@ takes at most %@.", clock(seconds), platform.title, clock(limit)),
                        frame: Int((limit * project.fps.value).rounded()), severity: .error,
                        fix: ReviewFix(hint: "Cut it down, or export a shorter version for this platform.")))
            }
            let vertical = project.height > project.width
            if platform.vertical != vertical || (!vertical && project.width == project.height) {
                issues.append(
                    ReviewIssue(
                        id: "output-shape-" + platform.id, title: "Frame does not match \(platform.title)",
                        detail: "\(platform.title) is \(platform.vertical ? "vertical (9:16)" : "landscape (16:9)"); the "
                            + "\(project.width) × \(project.height) frame would get bars.", frame: 0, severity: .error,
                        fix: ReviewFix(
                            command: "project.format",
                            arguments: ["canvas": .string(platform.vertical ? "portrait" : "landscape")])))
            }
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
    /// a key ending in `:` names a plugin provider and covers its issues; the longest matching key wins. `off` drops
    /// the issue.
    static func applyingSeverities(_ issues: [ReviewIssue], project: Project) -> [ReviewIssue] {
        let overrides = (project["review"]?.object["severities"]?.object ?? [:]).compactMapValues(\.string)
        guard !overrides.isEmpty else { return issues }
        let keys = overrides.keys.sorted { $0.count > $1.count }
        return issues.compactMap { issue in
            // A key ending in ':' names a plugin provider: it covers every issue that provider reported.
            guard let key = keys.first(where: { key in
                issue.id == key || issue.id.hasPrefix(key + "-")
                    || (key.hasSuffix(":") && issue.source.map { $0 + ":" == key } == true)
            }),
                let value = overrides[key]
            else { return issue }
            guard let severity = ReviewSeverity(rawValue: value) else { return value == "off" ? nil : issue }
            return ReviewIssue(
                id: issue.id, title: issue.title, detail: issue.detail, frame: issue.frame, endFrame: issue.endFrame,
                severity: severity, fix: issue.fix, source: issue.source)
        }
    }
}
