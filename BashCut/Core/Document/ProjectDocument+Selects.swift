import BashCutAutomation
import BashCutProject
import Foundation

/// The selects store (P1-D8): ranges the agent proposes and the user keeps or rejects, read and changed from the CLI,
/// MCP and the Media panel, and placed on Main as one undoable edit.
extension ProjectDocument {
    func registerSelectsCommands() {
        handle("selects.list") { document, arguments, _ in
            let status = arguments.optionalString("status")
            let selects = document.project.selects.filter { status == nil || $0.status == status }
            let all = document.project.selects
            return .object([
                "selects": .array(selects.map(\.json)),
                "counts": .object(Dictionary(uniqueKeysWithValues: ProjectSelect.statuses.map { name in
                    (name, JSONValue.integer(all.filter { $0.status == name }.count))
                })),
            ])
        }
        handleAuthored("selects.set") { document, arguments, author in
            guard case .array(let list)? = arguments["value"], !list.isEmpty else {
                throw RPCFailure(-32602, "Give a list of selects")
            }
            var selects = document.project.selects.map(\.fields)
            for entry in list {
                let id = entry.object["id"]?.string ?? UUID().uuidString.prefix(8).lowercased()
                var fields = entry.object
                fields["id"] = .string(id)
                if fields["status"] == nil { fields["status"] = .string("candidate") }
                if let index = selects.firstIndex(where: { $0["id"]?.string == id }) {
                    selects[index].merge(fields) { _, new in new }
                } else {
                    selects.append(fields)
                }
            }
            return try document.saveSelects(selects, label: "Update selects", author: author, base: arguments.int("baseRev"))
        }
        handleAuthored("selects.mark") { document, arguments, author in
            let ids = Set(try arguments.string("ids").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            let status = arguments.optionalString("status"), mustKeep = arguments.optionalBool("mustKeep")
            guard status != nil || mustKeep != nil else { throw RPCFailure(-32602, "Give status or mustKeep") }
            let selects: [[String: JSONValue]]
            do {
                selects = try document.project.markingSelects(
                    ids, status: status, mustKeep: mustKeep, reason: arguments.optionalString("reason"))
            } catch let error as ProjectError {
                throw RPCFailure.invalid(error)
            }
            return try document.saveSelects(selects, label: "Mark selects", author: author, base: arguments.int("baseRev"))
        }
        handleAuthored("selects.remove") { document, arguments, author in
            let ids = Set(try arguments.string("ids").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            let selects = document.project.selects.map(\.fields).filter { !ids.contains($0["id"]?.string ?? "") }
            return try document.saveSelects(selects, label: "Remove selects", author: author, base: arguments.int("baseRev"))
        }
        handleAuthored("selects.place") { document, arguments, author in
            let ids = arguments.optionalString("ids").map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
            let chosen = document.project.selects.filter { ids?.contains($0.id) ?? ($0.status == "kept") }
            let result = try document.placeSelects(
                chosen, at: arguments.optionalInt("atFrame"), author: author, baseRevision: arguments.int("baseRev"))
            return .object(["rev": .integer(result.revision), "items": .array(result.items.map(JSONValue.string))])
        }
    }

    func saveSelects(_ selects: [[String: JSONValue]], label: String, author: Author, base: Int?) throws -> JSONValue {
        do {
            let revision = try commit(
                .setProjectProperties(patch: ["selects": selects.isEmpty ? .null : .array(selects.map(JSONValue.object))]),
                label: label, author: author, baseRevision: base)
            return .object(["rev": .integer(revision), "selects": .array(project.selects.map(\.json))])
        } catch let error as ProjectError {
            throw RPCFailure.invalid(error)
        }
    }

    /// Lays `selects` in their order (`order`, else source start), from `frame` or the first one's layer end, one
    /// edit: pictures on Main, sound-only media (a podcast, a voice memo) on the dialogue layer.
    @discardableResult
    func placeSelects(
        _ selects: [ProjectSelect], at frame: Int?, author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, items: [String]) {
        guard !selects.isEmpty else { throw RPCFailure(-32602, "No selects to place (mark some kept, or give ids)") }
        let ordered = try selects.sorted(by: { ($0.order, $0.from) < ($1.order, $1.from) }).map { select in
            guard let media = project.media.first(where: { $0.id == select.media }) else {
                throw RPCFailure(-32602, "Select \(select.id): media \(select.media) is not in the project")
            }
            return (select: select, media: media, track: try project.selectTrackID(for: media))
        }
        var planner = LayerPlanner(project)
        var cursor = frame ?? project.insertionFrame(trackID: ordered[0].track, playhead: playhead)
        var items: [String] = []
        for (select, media, track) in ordered {
            let duration = Int(((select.to - select.from) * project.fps.value).rounded())
            guard duration > 0 else { continue }
            let id = UUID().uuidString
            try planner.placeMedia(
                media, on: track, at: cursor, duration: duration, itemID: id,
                sourceIn: Int((select.from * media.fps.value).rounded(.down)))
            items.append(id)
            cursor += duration
        }
        let revision = try commitPlan(planner, label: "Place selects", author: author, baseRevision: baseRevision)
        return (revision, items)
    }
}
