import Foundation

extension ProjectSchema {
    /// Top-level item fields the format declares. Others round-trip, but nothing reads them.
    public static let itemKeys = Set((definitions["item"]?.object["properties"]?.object ?? [:]).keys)
    /// Notes an agent may leave on an item; read by nobody, never warned about.
    static let noteKeys: Set<String> = ["note", "notes", "why", "reason", "comment"]

    /// One `unread-field` warning per item an edit gives fields nothing reads (`volume` instead of `volumeDb`), with
    /// the declared field closest to each name, so a no-op edit is visible in the same call.
    public static func unreadFieldWarnings(_ ops: [EditOperation]) -> [JSONValue] {
        var warnings: [JSONValue] = []
        func check(_ item: String, _ keys: some Collection<String>) {
            let unread = keys.filter { !itemKeys.contains($0) && !noteKeys.contains($0) }.sorted()
            guard !unread.isEmpty else { return }
            var suggest: [String: JSONValue] = [:]
            for key in unread { if let near = nearestItemKey(key) { suggest[key] = .string(near) } }
            let hint = suggest.keys.sorted().map { "\($0) → \(suggest[$0]?.string ?? "")" }.joined(separator: ", ")
            warnings.append(.object([
                "id": .string("unread-field"), "item": .string(item), "fields": .array(unread.map(JSONValue.string)),
                "detail": .string("Stored but not read, so it changes nothing: " + unread.joined(separator: ", ")
                    + (hint.isEmpty ? "; `schema get` lists the item fields" : "; did you mean " + hint)),
                "suggest": .object(suggest),
            ]))
        }
        for op in ops {
            switch op {
            case .setProperties(let id, let patch): check(id, patch.keys)
            case .insert(_, let item): check(item.id, item.fields.keys)
            case .group(_, _, let inner): warnings += unreadFieldWarnings(inner)
            default: break
            }
        }
        return warnings
    }

    /// The declared item field `key` most likely meant: one contains the other, else at most two edits away.
    static func nearestItemKey(_ key: String) -> String? {
        let lower = key.lowercased()
        if let match = itemKeys.sorted().first(where: { $0.lowercased().hasPrefix(lower) || lower.hasPrefix($0.lowercased()) }) {
            return match
        }
        let scored = itemKeys.map { ($0, NearestName.distance(lower, $0)) }.filter { $0.1 <= 2 }
        return scored.min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }?.0
    }
}
