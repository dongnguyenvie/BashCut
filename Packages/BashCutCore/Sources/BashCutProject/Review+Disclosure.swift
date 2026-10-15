import Foundation

extension TimelineReview {
    /// A warning per generated picture on screen (#550: media with `generated: true`) that is not covered for its whole
    /// span by a disclosure label: a text item marked `disclosure`, or one whose text is the project's disclosure
    /// label. `image disclose` adds the labels. Off unless the user turns on `review.credits`: by default nothing
    /// generated is labelled on the video, and AI disclosure is the platform's upload toggle.
    static func disclosureIssues(_ project: Project) -> [ReviewIssue] {
        guard ReviewProfile(project).credits else { return [] }
        let generated = Set(project.media.filter(\.isGenerated).map(\.id))
        guard !generated.isEmpty else { return [] }
        let label = project.disclosureText
        let labels = project.tracks.filter { $0.kind == TrackKind.text && !$0.isHidden }.flatMap(\.items).filter { item in
            item["disclosure"] == .bool(true) || (label != nil && item.text == label)
        }
        var issues: [ReviewIssue] = []
        for track in project.tracks where track.kind == TrackKind.video && !track.isHidden {
            for item in track.items.sorted(by: { $0.at < $1.at }) {
                guard let media = item.mediaID, generated.contains(media), item.duration > 0 else { continue }
                let uncovered = uncoveredFrames(item.at..<item.end, by: labels.map { $0.at..<$0.end })
                guard uncovered > 0 else { continue }
                issues.append(ReviewIssue(
                    id: "ai-undisclosed-" + item.id, title: "Generated picture without its label",
                    detail: "\(uncovered) of \(item.duration) frames show a generated picture with no disclosure label"
                        + (label.map { " (\"\($0)\")" } ?? "") + ".",
                    frame: item.at, endFrame: item.end, severity: .warning,
                    fix: ReviewFix(
                        command: "image.disclose",
                        hint: label == nil ? "Set the label with image style --disclosure or the brand kit first." : nil),
                    facts: ["media": .string(media), "uncoveredFrames": .integer(uncovered)]))
            }
        }
        return issues
    }

    /// Frames of `span` that no range in `cover` reaches.
    public static func uncoveredFrames(_ span: Range<Int>, by cover: [Range<Int>]) -> Int {
        var covered = 0
        var cursor = span.lowerBound
        for range in cover.map({ $0.clamped(to: span) }).filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if range.upperBound <= cursor { continue }
            covered += range.upperBound - max(cursor, range.lowerBound)
            cursor = range.upperBound
        }
        return span.count - covered
    }
}
