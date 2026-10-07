import Foundation

/// What a review run actually looked at (P1-E5): checks measured for this revision, measured for an older one
/// (stale), not checked at all, plugin checks that failed or timed out, picture checks that cannot be trusted because
/// the picture barely changes, and the review limits the project has not set. A review without these is not a pass.
extension TimelineReview {
    /// Every picture sample is still: black, frozen and jump checks cannot tell a static edit from a broken one.
    static func pictureUnreliable(_ project: Project, context: ReviewContext) -> Bool {
        guard let picture = context.picture, picture.revision == project.revision, picture.samples.count > 1 else { return false }
        return picture.samples.dropFirst().allSatisfy(\.isStill)
    }

    static func unreliableIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        guard pictureUnreliable(project, context: context) else { return [] }
        return [ReviewIssue(
            id: "picture-unreliable", title: "Picture checks cannot be trusted",
            detail: "The picture barely changes anywhere in the edit, so black, frozen and jump-cut checks did not pass; "
                + "they could not tell. Look at the frames (timeline sheet).",
            frame: 0, severity: .info, fix: ReviewFix(command: "timeline.sheet"))]
    }

    public static func coverage(_ project: Project, context: ReviewContext) -> JSONValue {
        var measured: [String] = [], stale: [String] = [], notChecked: [String] = [], failed: [JSONValue] = []
        let state = { (name: String, revision: Int?, how: String) in
            switch revision {
            case project.revision?: measured.append(name)
            case nil: notChecked.append("\(name) (\(how))")
            default: stale.append("\(name) (revision \(revision ?? 0); \(how))")
            }
        }
        state("picture", context.picture?.revision, "review measure")
        state("loudness", context.loudness?.revision, "a normalized export")
        state("plugin checks", context.pluginIssues?.revision, "review measure")
        for issue in context.pluginIssues?.issues ?? [] where issue.id.hasSuffix(":failed") {
            failed.append(.object([
                "check": .string(String(issue.id.dropLast(":failed".count))),
                "timedOut": .bool(issue.detail.contains("did not finish")), "detail": .string(issue.detail),
            ]))
        }
        if context.transcripts.isEmpty { notChecked.append("cuts inside words (no stored transcripts: media transcribe)") } else {
            measured.append("cuts inside words")
        }
        if context.missingGlyphs == nil { notChecked.append("glyphs") } else { measured.append("glyphs") }
        if context.targets.platforms.isEmpty { notChecked.append("platform zones and length (no outputs: project format --outputs)") } else {
            measured.append("platform zones and length")
        }
        let profile = ReviewProfile(project)
        return .object([
            "revision": .integer(project.revision), "measured": .array(measured.map(JSONValue.string)),
            "stale": .array(stale.map(JSONValue.string)), "notChecked": .array(notChecked.map(JSONValue.string)),
            "failed": .array(failed),
            "unreliable": .array(pictureUnreliable(project, context: context) ? [.string("picture: it barely changes")] : []),
            "unsetLimits": .array(ReviewProfile.numberKeys.keys.filter { profile[$0] == nil }.sorted().map(JSONValue.string)),
        ])
    }
}
