import BashCutAutomation
import BashCutProject
import Foundation

/// Clip gain: `clip.volume` sets `volumeDb` on clips and their linked partners as one undoable edit, the one-liner
/// for the `setProperties` op with patch {volumeDb} (#628).
extension ProjectDocument {
    /// Sets the gain of `ids` (with their linked partners) to `db` as one undo step. Returns the revision and the
    /// items left out; throws when none has sound. Items already at `db` are not edited again.
    @discardableResult
    func setClipVolume(
        _ db: Double, items ids: [String], author: Author = .user, baseRevision: Int? = nil
    ) throws -> (revision: Int, skipped: [String]) {
        let (operations, skipped) = try project.volumeOperations(ids, db: db)
        guard !operations.isEmpty else {
            throw ProjectError.invalid("None of the items is a clip with sound (audio, or video with media)")
        }
        let items = Dictionary(project.tracks.flatMap(\.items).map { ($0.id, $0) }) { first, _ in first }
        let changing = operations.filter { operation in
            guard case .setProperties(let id, _) = operation else { return true }
            return abs((items[id]?["volumeDb"]?.double ?? 0) - db) > 0.0001
        }
        guard !changing.isEmpty else { return (project.revision, skipped) }
        let label = String(format: "Volume %+.1f dB", db)
        let revision = try commit(
            .group(label: label, author: author, ops: changing), label: label, author: author, baseRevision: baseRevision)
        return (revision, skipped)
    }

    func registerVolumeCommands() {
        handleAuthored("clip.volume") { document, arguments, author in
            let listed = (arguments.optionalString("items") ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let ids = listed.isEmpty ? [arguments.optionalString("item") ?? document.selectedID].compactMap { $0 } : listed
            guard !ids.isEmpty else { throw RPCFailure(-32602, "Give an item or select a clip first") }
            guard let db = arguments.optionalDouble("db") else { throw RPCFailure(-32602, "db is required") }
            let (revision, skipped) = try document.setClipVolume(
                db, items: ids, author: author, baseRevision: try arguments.int("baseRev"))
            let items = Dictionary(document.project.tracks.flatMap(\.items).map { ($0.id, $0) }) { first, _ in first }
            func row(_ id: String) -> [String: JSONValue] {
                [
                    "item": .string(id), "volumeDb": .number(items[id]?["volumeDb"]?.double ?? 0),
                    "linked": items[id]?.linkedItemID.map(JSONValue.string) ?? .null,
                ]
            }
            if listed.isEmpty, let id = ids.first {
                guard !skipped.contains(id) else { throw RPCFailure(-32602, "\(id) is not a clip with sound") }
                return .object(row(id).merging(["rev": .integer(revision)]) { $1 })
            }
            return .object([
                "rev": .integer(revision),
                "items": .array(ids.filter { !skipped.contains($0) }.map { .object(row($0)) }),
                "skipped": .array(skipped.map(JSONValue.string)),
            ])
        }
    }
}
