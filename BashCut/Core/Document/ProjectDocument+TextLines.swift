import BashCutAutomation
import BashCutProject
import Foundation

/// Per-line looks of a text item (`textStyle.lines`, text phase 2): Inspector › Text › Lines and `text.line-style`.
extension ProjectDocument {
    /// Merges `patch` into line `line` (from the top; negative from the bottom) of text item `id` (the selection by
    /// default), or drops the line's look with `clear`. One undoable `setProperties` of the item's `textStyle`.
    @discardableResult
    func setLineStyle(
        _ patch: [String: JSONValue], line: Int, clear: Bool = false, item id: String? = nil, author: Author = .user,
        baseRevision: Int? = nil, coalesce: Bool = false
    ) throws -> Int {
        guard let id = id ?? selectedID,
            let track = project.tracks.first(where: { $0.items.contains { $0.id == id } }), track.kind == TrackKind.text,
            let item = track.items.first(where: { $0.id == id })
        else { throw ProjectError.invalid("Give a text item (or select one)") }
        let count = item.text.components(separatedBy: "\n").count
        guard let index = TextLineStyles.index(line, count: count) else {
            throw ProjectError.invalid("The text has \(count) line\(count == 1 ? "" : "s"); line \(line) is not one of them")
        }
        let style = try TextLineStyles.setting(item["textStyle"]?.object ?? [:], line: index, patch: patch, clear: clear)
        return try commit(
            .setProperties(item: id, patch: ["textStyle": .object(style)]), label: "Line style", author: author,
            baseRevision: baseRevision, coalescingKey: coalesce ? "line-style.\(id).\(index)" : nil)
    }

    func registerTextLineCommands() {
        handleAuthored("text.line-style") { document, arguments, author in
            var patch: [String: JSONValue] = [:]
            for key in ["font", "fill", "stroke"] {
                if let value = arguments.optionalString(key) { patch[key] = value == "none" ? .null : .string(value) }
            }
            if let scale = arguments.optionalDouble("scale") { patch["scale"] = .number(scale) }
            let clear = arguments.bool("clear")
            guard clear || !patch.isEmpty else { throw RPCFailure(-32602, "Give font, scale, fill, stroke or clear") }
            let id = arguments.optionalString("item") ?? document.selectedID
            let revision = try document.setLineStyle(
                patch, line: try arguments.int("line"), clear: clear, item: id, author: author,
                baseRevision: try arguments.int("baseRev"))
            let item = document.project.tracks.flatMap(\.items).first { $0.id == id }
            return .object([
                "rev": .integer(revision), "item": id.map(JSONValue.string) ?? .null,
                "lines": item?["textStyle"]?.object["lines"] ?? .null,
            ])
        }
    }
}
