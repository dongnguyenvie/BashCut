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

    /// The graphics plugin's command that renders `drafts` at full quality and swaps every use: `graphic plan --final`
    /// when every draft is a `plan.cut` graphic's media, else `graphic rerender --all --final` (it finalises placed
    /// ones too). The export guard, the Export panel's notice and the review's `graphic-draft` warning name it.
    public static func graphicDraftFix(_ project: Project, drafts: [GraphicDraft]) -> String {
        let planned = Set(
            (project["plan"]?.object["cut"]?.object["graphics"]?.array ?? []).compactMap { $0.object["media"]?.string })
        return drafts.allSatisfy { planned.contains($0.media) }
            ? "bin/graphic plan --final" : "bin/graphic rerender --all --final"
    }

    /// Before a final export (any preset but quick-draft): no draft graphic on the timeline; the fix is
    /// `graphicDraftFix`.
    public static func graphicsDraftGuard(_ project: Project) -> GuardFailure? {
        let drafts = graphicDrafts(project)
        guard !drafts.isEmpty else { return nil }
        let command = graphicDraftFix(project, drafts: drafts)
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

// MARK: Fingerprint

extension WorkflowChecklist {
    /// The fields of `data.graphics` that only say how a graphic was rendered: a draft and its final render differ in
    /// them alone (HyperFrames records the full fps on both; `frames` counts the render's own frames).
    static let graphicRenderFields: Set<String> = ["draft", "fps", "frames"]

    /// `project.tracks` for the timeline fingerprint, with every item that shows a plugin graphic (media with
    /// `data.graphics`) pointing at the graphic instead of its render: `media` becomes the recorded inputs without
    /// `graphicRenderFields`, `in` the project frame it starts at, and `dur` `"end"` when the item plays to the
    /// render's last frame. A draft swapped for its final render (`graphic plan --final`, `rerender --all --final`:
    /// new media at another fps, `in` and a played-through length rescaled) keeps the fingerprint; changing the
    /// graphic's inputs or any other field of the item does not (#634).
    static func graphicTracks(_ project: Project) -> JSONValue {
        let tracks = project["tracks"] ?? .null
        let graphics = project.media.filter { $0.fields["data"]?.object["graphics"]?.object.isEmpty == false }
        let projectFPS = project.fps.value
        guard !graphics.isEmpty, projectFPS > 0, case .array(let list) = tracks else { return tracks }
        let byID = Dictionary(graphics.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return .array(list.map { track in
            guard case .object(var fields) = track, case .array(let items) = fields["items"] else { return track }
            fields["items"] = .array(items.map { value in
                guard case .object(var item) = value, let media = item["media"]?.string.flatMap({ byID[$0] }),
                    media.fps.value > 0
                else { return value }
                var graphic = media.fields["data"]?.object["graphics"]?.object ?? [:]
                for key in graphicRenderFields { graphic[key] = nil }
                let toProject = { (frames: Int) in Double(frames) / media.fps.value * projectFPS }
                let start = Int(toProject(item["in"]?.int ?? 0).rounded())
                item["media"] = .object(["graphic": .object(graphic)])
                item["in"] = .integer(start)
                let length = Int((toProject(media.frames) + 1e-6).rounded(.down))
                if let duration = item["dur"]?.int, start + duration >= length { item["dur"] = .string("end") }
                return .object(item)
            })
            return .object(fields)
        })
    }
}
