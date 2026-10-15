import BashCutAutomation
import BashCutProject
import Foundation

/// The item backdrop (P3-J7): Inspector › Video › Backdrop and `clip.backdrop`.
extension ProjectDocument {
    /// Sets (or with nil removes) the `backdrop` of video items `ids` (the selection by default) in one undo step.
    @discardableResult
    func setBackdrop(
        _ backdrop: [String: JSONValue]?, items ids: [String]? = nil, author: Author = .user, baseRevision: Int? = nil,
        coalesce: Bool = false
    ) throws -> Int {
        let ids = ids ?? selectedIDs
        guard !ids.isEmpty else { throw ProjectError.invalid("Give a video clip or image (or select one)") }
        for id in ids {
            guard let track = project.tracks.first(where: { $0.items.contains { $0.id == id } }) else {
                throw ProjectError.invalid("Unknown item \(id)")
            }
            guard track.kind == TrackKind.video, track.items.first(where: { $0.id == id })?.mediaID != nil else {
                throw ProjectError.invalid("Item \(id) is not a video clip or image")
            }
        }
        let value: JSONValue = backdrop.map { .object($0) } ?? .null
        let operations = ids.map { EditOperation.setProperties(item: $0, patch: ["backdrop": value]) }
        let label = backdrop == nil ? "Remove backdrop" : "Backdrop"
        return try commit(
            operations.count == 1 ? operations[0] : .group(label: label, author: author, ops: operations), label: label,
            author: author, baseRevision: baseRevision,
            coalescingKey: coalesce ? "backdrop." + ids.joined(separator: ",") : nil)
    }

    /// `clip.reframe`, `text.line-style`, `clip.backdrop` and `clip.transition`.
    func registerPictureCommands() {
        registerReframeCommands()
        registerTextLineCommands()
        registerBackdropCommands()
        registerItemTransitionCommands()
    }

    func registerBackdropCommands() {
        handleAuthored("clip.backdrop") { document, arguments, author in
            let listed = (arguments.optionalString("items") ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let ids = !listed.isEmpty ? listed : arguments.optionalString("item").map { [$0] }
            let kind = try arguments.string("kind")
            var backdrop: [String: JSONValue]?
            if kind != "none" {
                var fields: [String: JSONValue] = ["kind": .string(kind)]
                if let color = arguments.optionalString("color") { fields["color"] = .string(color) }
                if let blur = arguments.optionalDouble("blur") { fields["blur"] = .number(blur) }
                if let dim = arguments.optionalDouble("dim") { fields["dim"] = .number(dim) }
                backdrop = fields
            }
            let revision = try document.setBackdrop(
                backdrop, items: ids, author: author, baseRevision: try arguments.int("baseRev"))
            return .object([
                "rev": .integer(revision), "items": .array((ids ?? document.selectedIDs).map(JSONValue.string)),
                "backdrop": backdrop.map { .object($0) } ?? .null,
            ])
        }
    }
}
