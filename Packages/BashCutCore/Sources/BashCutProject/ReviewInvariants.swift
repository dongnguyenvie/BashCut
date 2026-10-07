import Foundation

/// The checks that are errors with no review settings (P1-E1), besides gaps, black picture, missing fonts and the
/// platform's length and shape: a clip edge that cuts through a spoken word, and text with characters its font cannot
/// draw. Neither has a threshold beyond measurement precision: a word cut by less than one frame is timing noise.
extension TimelineReview {
    /// Each clip edge that falls inside a transcribed word of the clip's media, unless the next or previous clip on
    /// the track continues the same source there (a plain split).
    public static func wordCutIssues(_ project: Project, transcripts: [String: SourceTranscript]) -> [ReviewIssue] {
        let fps = project.fps.value
        var issues: [ReviewIssue] = []
        for (mediaID, transcript) in transcripts.sorted(by: { $0.key < $1.key }) {
            let words = transcript.words.filter { $0.event == nil && $0.end > $0.start }
            guard !words.isEmpty else { continue }
            for (clip, asset) in project.audibleClips(mediaID) where asset.fps.value > 0 {
                let span = project.sourceSpan(of: clip, media: asset)
                let track = project.tracks.first { $0.items.contains { $0.id == clip.id } }
                let neighbours = track?.items ?? []
                let continuesBefore = neighbours.contains { other in
                    other.end == clip.at && other.mediaID == clip.mediaID
                        && abs(project.sourceSpan(of: other, media: asset).upperBound - span.lowerBound) < 1 / fps
                }
                let continuesAfter = neighbours.contains { other in
                    other.at == clip.end && other.mediaID == clip.mediaID
                        && abs(project.sourceSpan(of: other, media: asset).lowerBound - span.upperBound) < 1 / fps
                }
                let edges = [(edge: "in", source: span.lowerBound, skip: continuesBefore),
                             (edge: "out", source: span.upperBound, skip: continuesAfter)]
                for edge in edges where !edge.skip {
                    guard let word = words.first(where: {
                        $0.start + 1 / fps <= edge.source && edge.source <= $0.end - 1 / fps
                    }) else { continue }
                    let into = edge.source - word.start
                    issues.append(
                        ReviewIssue(
                            id: "cut-in-word-\(clip.id)-\(edge.edge)", title: "Cut inside a word",
                            detail: String(
                                format: "The clip %@ %.2f s into “%@” (%.2f–%.2f s in the source).",
                                edge.edge == "in" ? "starts" : "ends", into, word.text, word.start, word.end),
                            frame: edge.edge == "in" ? clip.at : max(clip.at, clip.end - 1), severity: .error,
                            fix: ReviewFix(hint: "Trim the edge to a word boundary (transcript words --heard gives the "
                                + "edges), or cover the cut with other sound and say why.")))
                }
            }
        }
        return issues
    }

    /// Text items with characters their font has no glyphs for; once per font and set of characters.
    static func glyphIssues(_ project: Project, missing: ((Item) -> (font: String, characters: String)?)?) -> [ReviewIssue] {
        guard let missing else { return [] }
        var seen = Set<String>()
        var issues: [ReviewIssue] = []
        for text in project.tracks.filter({ $0.kind == TrackKind.text }).flatMap(\.items).sorted(by: { $0.at < $1.at }) {
            guard let found = missing(text), !found.characters.isEmpty,
                seen.insert(found.font + "|" + found.characters).inserted
            else { continue }
            issues.append(
                ReviewIssue(
                    id: "glyph-" + text.id, title: "Characters the font cannot draw",
                    detail: "\(found.font) has no glyphs for “\(found.characters)”; they draw in another font.",
                    frame: text.at, severity: .error,
                    fix: ReviewFix(hint: "Pick a font that covers the language (fonts list), or import one (fonts import).")))
        }
        return issues
    }

    /// A stable place on the timeline for issues found at a frame: the Main clip there and the offset into it, so
    /// the ID survives edits elsewhere (P1-E2). Without a clip there, the frame.
    static func anchor(_ project: Project, frame: Int) -> String {
        let main = project.tracks.first { $0.role == TrackRole.main }?.items ?? []
        guard let clip = main.first(where: { $0.at <= frame && frame < $0.end }) else { return "\(frame)" }
        return "\(clip.id)+\(frame - clip.at)"
    }
}

/// What changed between two review runs (P1-E2): issues fixed since, new and still there, by stable ID.
public enum ReviewRounds {
    public static func diff(before: [ReviewIssue], after: [ReviewIssue]) -> JSONValue {
        let old = Set(before.map(\.id)), new = Set(after.map(\.id))
        let row = { (issue: ReviewIssue) -> JSONValue in
            .object(["id": .string(issue.id), "title": .string(issue.title), "severity": .string(issue.severity.rawValue)])
        }
        return .object([
            "fixed": .array(before.filter { !new.contains($0.id) }.map(row)),
            "new": .array(after.filter { !old.contains($0.id) }.map(row)),
            "persisting": .array(after.filter { old.contains($0.id) }.map(row)),
        ])
    }
}

extension TimelineReview {
    /// Open issues whose ID starts with one of the project's `review.blockExport` prefixes (P1-E1): an export of the
    /// project refuses while any is left. Empty without the setting.
    public static func blockingExport(_ project: Project, issues: [ReviewIssue]) -> [ReviewIssue] {
        let prefixes = project["review"]?.object["blockExport"]?.array.compactMap(\.string) ?? []
        guard !prefixes.isEmpty else { return [] }
        return issues.filter { issue in
            issue.accepted == nil && prefixes.contains { issue.id == $0 || issue.id.hasPrefix($0 + "-") }
        }
    }
}
