import Foundation

/// Graphics rendered as drafts (#634): a graphics plugin records `data.graphics.draft: true` on a review render
/// (HyperFrames `--draft`: fewer frames a second, faster capture). A final export must not ship one.
extension WorkflowChecklist {
    /// A draft graphic the timeline uses: its media, the plugin's name for it and the items that show it.
    public struct GraphicDraft: Equatable, Sendable {
        public let media: String
        public let name: String
        public let items: [String]
    }

    /// Draft media used by at least one timeline item, in media order; media without `data.graphics` never counts.
    public static func graphicDrafts(_ project: Project) -> [GraphicDraft] {
        let drafts = project.media.filter { $0.fields["data"]?.object["graphics"]?.object["draft"] == .bool(true) }
        guard !drafts.isEmpty else { return [] }
        var uses: [String: [String]] = [:]
        for item in project.tracks.flatMap(\.items) {
            if let media = item.mediaID { uses[media, default: []].append(item.id) }
        }
        return drafts.compactMap { media in
            guard let items = uses[media.id] else { return nil }
            let name = media.fields["data"]?.object["graphics"]?.object["name"]?.string ?? media.fileName
            return GraphicDraft(media: media.id, name: name, items: items)
        }
    }

    /// Before a final export (any preset but quick-draft): no draft graphic on the timeline. The fix renders them at
    /// full quality and swaps every use: `graphic plan --final` when every draft is a `plan.cut` graphic's media, else
    /// `graphic rerender --all --final` (it finalises placed ones too).
    public static func graphicsDraftGuard(_ project: Project) -> GuardFailure? {
        let drafts = graphicDrafts(project)
        guard !drafts.isEmpty else { return nil }
        let planned = Set(
            (project["plan"]?.object["cut"]?.object["graphics"]?.array ?? []).compactMap { $0.object["media"]?.string })
        let command = drafts.allSatisfy { planned.contains($0.media) }
            ? "bin/graphic plan --final" : "bin/graphic rerender --all --final"
        let list = drafts.map { "\($0.name) (media \($0.media); items \($0.items.joined(separator: ", ")))" }
        return GuardFailure(
            category: "graphics_draft",
            message: "\(drafts.count) graphic(s) on the timeline are draft renders: \(list.joined(separator: "; ")). "
                + "Render them at full quality first with the graphics plugin (\(command)), then export again; only "
                + "quick-draft exports may use drafts",
            command: command,
            details: [
                "drafts": .array(drafts.map { draft in
                    .object([
                        "media": .string(draft.media), "name": .string(draft.name),
                        "items": .array(draft.items.map(JSONValue.string)),
                    ])
                })
            ])
    }
}
