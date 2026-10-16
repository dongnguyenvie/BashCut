import Foundation

extension TimelineReview {
    /// A warning per graphic on the timeline that a plugin rendered as a draft (#634: media with
    /// `data.graphics.draft`), so `review run`, `plan check` and the critic see drafts before the export gate. A
    /// quick-draft export may ship them; a final export by an agent is refused (`graphics_draft`).
    static func graphicDraftIssues(_ project: Project) -> [ReviewIssue] {
        let drafts = WorkflowChecklist.graphicDrafts(project)
        guard !drafts.isEmpty else { return [] }
        let command = WorkflowChecklist.graphicDraftFix(project, drafts: drafts)
        let starts = Dictionary(
            project.tracks.flatMap(\.items).map { ($0.id, ($0.at, $0.end)) }, uniquingKeysWith: { first, _ in first })
        return drafts.map { draft in
            let spans = draft.items.compactMap { starts[$0] }
            return ReviewIssue(
                id: "graphic-draft-" + draft.media, title: "Draft graphic",
                detail: "\(draft.name) is a draft render (fewer frames a second); render it at full quality before "
                    + "the final export.",
                frame: spans.map(\.0).min() ?? 0, endFrame: spans.map(\.1).max(), severity: .warning,
                fix: ReviewFix(hint: "Run the graphics plugin's final render: \(command)."),
                facts: [
                    "media": .string(draft.media), "name": .string(draft.name),
                    "items": .array(draft.items.map(JSONValue.string)), "command": .string(command),
                ])
        }
    }
}
