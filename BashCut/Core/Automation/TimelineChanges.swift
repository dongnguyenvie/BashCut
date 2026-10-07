import BashCutProject
import CryptoKit
import Foundation

/// The identity of a planned edit (P2-G3): the operations and the revision they apply to. A dry run returns it; an
/// apply with `expectFingerprint` refuses operations that differ from the ones that were reviewed.
public enum EditFingerprint {
    public static func of(_ operations: [EditOperation], baseRevision: Int) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data("bashcut.edit/1 rev \(baseRevision)\n".utf8)
        data.append(try encoder.encode(operations))
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// Recent edits from the undo history, newest first (P2-G3): label, author, why, evidence, when, the revision each
/// produced and a short change digest; then the undone edits redo would bring back.
public enum TimelineChanges {
    /// `author` keeps one author (`user`, `claude`, …) or, as `agent`, every agent author.
    public static func json(
        history: ProjectHistory, limit: Int, author: String? = nil, isAgent: (Author) -> Bool
    ) -> JSONValue {
        let undo = history.undoEntries
        func keep(_ entry: HistoryEntry) -> Bool {
            guard let author else { return true }
            return author == "agent" ? isAgent(entry.author) : entry.author.rawValue == author
        }
        var edits: [JSONValue] = []
        // Each step's snapshot is the project before it; the project after it is the next step's snapshot.
        var after = history.project
        var step = 0
        for entry in undo.reversed() {
            step += 1
            defer { if let before = entry.before { after = before } }
            guard keep(entry), edits.count < limit else { continue }
            var fields = describe(entry)
            fields["step"] = .integer(step)
            if let before = entry.before {
                let digest = ChangeDigest.json(before: before, after: after, limit: 8).object
                fields["changes"] = .object(digest.filter { ["counts", "text", "truncated"].contains($0.key) })
            }
            edits.append(.object(fields))
        }
        let undone = history.redoEntries.reversed().filter(keep).prefix(limit).map { JSONValue.object(describe($0)) }
        return .object([
            "rev": .integer(history.project.revision),
            "edits": .array(edits),
            "undone": .array(Array(undone)),
            "counts": .object(["undoable": .integer(undo.count), "redoable": .integer(history.redoEntries.count)]),
        ])
    }

    private static func describe(_ entry: HistoryEntry) -> [String: JSONValue] {
        var fields: [String: JSONValue] = ["label": .string(entry.label), "author": .string(entry.author.rawValue)]
        if let why = entry.note?.why { fields["why"] = .string(why) }
        if let evidence = entry.note?.evidence, !evidence.isEmpty { fields["evidence"] = .array(evidence.map(JSONValue.string)) }
        if let revision = entry.revision { fields["rev"] = .integer(revision) }
        if let date = entry.date { fields["at"] = .string(date.formatted(.iso8601)) }
        return fields
    }
}
