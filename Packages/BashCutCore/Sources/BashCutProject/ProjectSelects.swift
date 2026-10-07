import Foundation

/// Candidate, kept and rejected source ranges with why (P1-D8): `selects` in the project, each `{id, media, from, to
/// (source seconds), status, quote?, reason?, evidence?, mustKeep?, order?}`. The agent proposes, the user overrides
/// in the Media panel, and `selects place` lays the kept ones on Main as one edit.
public struct ProjectSelect: Sendable, Equatable {
    public static let statuses = ["candidate", "kept", "rejected"]

    public var fields: [String: JSONValue]

    public init(fields: [String: JSONValue]) { self.fields = fields }

    public var id: String { fields["id"]?.string ?? "" }
    public var media: String { fields["media"]?.string ?? "" }
    public var from: Double { fields["from"]?.double ?? 0 }
    public var to: Double { fields["to"]?.double ?? 0 }
    public var status: String { fields["status"]?.string ?? "candidate" }
    public var mustKeep: Bool { fields["mustKeep"]?.bool ?? false }
    public var quote: String? { fields["quote"]?.string }
    public var reason: String? { fields["reason"]?.string }
    public var order: Double { fields["order"]?.double ?? from }
    public var json: JSONValue { .object(fields) }
}

extension Project {
    public var selects: [ProjectSelect] {
        self["selects"]?.array.map { ProjectSelect(fields: $0.object) } ?? []
    }

    /// Each select has a unique ID, a media ID, from < to and a known status. The media may be gone (removing media
    /// must not fail on its selects); placing such a select fails instead.
    func validateSelects() throws {
        guard let value = self["selects"], value != .null else { return }
        guard case .array(let list) = value, list.count <= 2_000 else { throw ProjectError.invalid("selects: expected up to 2000") }
        var seen = Set<String>()
        for (index, entry) in list.enumerated() {
            let select = ProjectSelect(fields: entry.object)
            guard case .object = entry, !select.id.isEmpty, seen.insert(select.id).inserted, !select.media.isEmpty,
                let from = entry.object["from"]?.double, let to = entry.object["to"]?.double, from >= 0, from < to,
                ProjectSelect.statuses.contains(select.status),
                entry.object["mustKeep"].map({ $0.bool != nil }) ?? true
            else {
                throw ProjectError.invalid(
                    "selects[\(index)]: expected a unique id, a media ID, 0 ≤ from < to and status candidate, kept or rejected")
            }
        }
    }
}

extension TimelineReview {
    /// A must-keep select no clip plays any of (P1-D8) — the project asked for it, so a warning.
    static func mustKeepIssues(_ project: Project) -> [ReviewIssue] {
        let media = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let clips = project.tracks.filter { $0.kind == TrackKind.video || $0.kind == TrackKind.audio }.flatMap(\.items)
        return project.selects.filter { $0.mustKeep && $0.status != "rejected" }.compactMap { select in
            let played = clips.contains { clip in
                guard clip.mediaID == select.media, let asset = media[select.media] else { return false }
                let span = project.sourceSpan(of: clip, media: asset)
                return span.lowerBound < select.to && span.upperBound > select.from
            }
            guard !played else { return nil }
            return ReviewIssue(
                id: "must-keep-" + select.id, title: "A must-keep select is not in the edit",
                detail: String(format: "%@ %.1f–%.1f s", select.media, select.from, select.to)
                    + (select.quote.map { ": “\($0)”" } ?? "") + " is marked must keep.",
                frame: 0, severity: .warning, fix: ReviewFix(command: "selects.place", hint: "Place it, or unmark it with a reason."))
        }
    }
}
