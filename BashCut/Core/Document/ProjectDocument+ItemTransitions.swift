import BashCutAutomation
import BashCutProject
import Foundation

/// An item's own entrance and exit (`enter`, `exit`): Inspector › In and Out, a transition tile dropped on a text or
/// overlay item, and `clip.transition`.
extension ProjectDocument {
    /// The length a new entrance or exit gets: half a second, at most a third of the item.
    func defaultItemTransitionFrames(for item: Item) -> Int {
        max(1, min(Int((project.fps.value / 2).rounded()), item.duration / 3))
    }

    /// Sets (or with a nil `kind` removes) the `field` (`enter` or `exit`) of items `ids` (the selection by default)
    /// in one undo step. A missing duration or easing keeps the item's own, else a default; other fields are kept.
    @discardableResult
    func setItemTransition(
        _ field: String, kind: String?, frames: Int? = nil, easing: String? = nil, items ids: [String]? = nil,
        author: Author = .user, baseRevision: Int? = nil
    ) throws -> Int {
        try setItemTransitions([field], kind: kind, frames: frames, easing: easing, items: ids, author: author,
                               baseRevision: baseRevision)
    }

    /// `setItemTransition` of several fields (`enter`, `exit`) in one undo step.
    @discardableResult
    func setItemTransitions(
        _ fields: [String], kind: String?, frames: Int? = nil, easing: String? = nil, items ids: [String]? = nil,
        author: Author = .user, baseRevision: Int? = nil
    ) throws -> Int {
        guard !fields.isEmpty, fields.allSatisfy(ItemTransition.fields.contains) else {
            throw ProjectError.invalid("Use enter or exit")
        }
        let ids = ids ?? selectedIDs
        guard !ids.isEmpty else { throw ProjectError.invalid("Give a text, sticker or overlay item (or select one)") }
        let items = project.tracks.flatMap(\.items)
        let operations = try ids.map { id -> EditOperation in
            guard let item = items.first(where: { $0.id == id }) else { throw ProjectError.invalid("Unknown item \(id)") }
            var patch: [String: JSONValue] = [:]
            for field in fields {
                guard let kind else {
                    patch[field] = .null
                    continue
                }
                var value = item[field]?.object ?? [:]
                if value["kind"]?.string != kind { value["motion"] = nil }
                value["kind"] = .string(kind)
                value["duration"] = .integer(frames ?? value["duration"]?.int ?? defaultItemTransitionFrames(for: item))
                if let easing { value["easing"] = easing == TimelineTransition.defaultEasing ? nil : .string(easing) }
                patch[field] = .object(value)
            }
            return .setProperties(item: id, patch: patch)
        }
        let name = fields.count > 1 ? "In and Out" : fields[0] == "enter" ? "In" : "Out"
        let label = kind.map { "\(name): \($0)" } ?? "Remove \(name)"
        return try commit(
            operations.count == 1 ? operations[0] : .group(label: label, author: author, ops: operations), label: label,
            author: author, baseRevision: baseRevision)
    }

    /// A transition tile dropped on the timeline: on a clip beside a cut it sets that cut's transition; on any other
    /// video or text item under the pointer (on the layer it is over, else any) it sets the item's In.
    func applyDroppedTransition(kind: String, at frame: Int, overTrack trackID: String?) {
        let tracks = project.tracks.filter { $0.kind == TrackKind.video || $0.kind == TrackKind.text }
        let under = tracks.filter { trackID == nil || $0.id == trackID }.flatMap(\.items)
            .first { $0.at <= frame && frame < $0.end }
        guard let item = under else {
            message = String(localized: "Drop a transition on a clip, text or sticker")
            return
        }
        selectedIDs = [item.id]
        if videoCut(at: item.id) != nil {
            setSelectedTransition(kind: kind)
        } else {
            do { try setItemTransition("enter", kind: kind, items: [item.id]) } catch {
                message = error.localizedDescription
            }
        }
    }

    func registerItemTransitionCommands() {
        handleAuthored("clip.transition") { document, arguments, author in
            let listed = (arguments.optionalString("items") ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let ids = !listed.isEmpty ? listed : arguments.optionalString("item").map { [$0] }
            let side = try arguments.string("side")
            let kind = try arguments.string("kind")
            let fields = side == "both" ? ItemTransition.fields : [side == "in" ? "enter" : side == "out" ? "exit" : side]
            let revision = try document.setItemTransitions(
                fields, kind: kind == "none" ? nil : kind, frames: arguments.optionalInt("frames"),
                easing: arguments.optionalString("easing"), items: ids, author: author,
                baseRevision: try arguments.int("baseRev"))
            let items = document.project.tracks.flatMap(\.items)
            return .object([
                "rev": .integer(revision),
                "items": .array((ids ?? document.selectedIDs).map { id in
                    let item = items.first { $0.id == id }
                    return .object([
                        "id": .string(id), "enter": item?["enter"] ?? .null, "exit": item?["exit"] ?? .null,
                    ])
                }),
            ])
        }
    }
}
