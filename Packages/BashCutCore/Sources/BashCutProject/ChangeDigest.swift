import Foundation

/// What an edit changed, bounded (P2-G1): items added, removed and modified (with the fields that changed), layers
/// and project fields, at most `limit` rows per list with `truncated`, and the same as `+ ~ -` lines. Agents read it
/// instead of reading the whole timeline again after each edit.
public enum ChangeDigest {
    public static func json(before: Project, after: Project, limit: Int = 40) -> JSONValue {
        let index = { (project: Project) -> [String: (track: String, item: Item)] in
            Dictionary(project.tracks.flatMap { track in track.items.map { ($0.id, (track.id, $0)) } }, uniquingKeysWith: { first, _ in first })
        }
        let old = index(before), new = index(after)
        let added = new.keys.filter { old[$0] == nil }.sorted { (new[$0]?.item.at ?? 0, $0) < (new[$1]?.item.at ?? 0, $1) }
        let removed = old.keys.filter { new[$0] == nil }.sorted()
        var modified: [(String, [String])] = []
        for id in new.keys.sorted() {
            guard let was = old[id], let now = new[id] else { continue }
            var fields = Set(was.item.fields.keys).union(now.item.fields.keys).filter { was.item.fields[$0] != now.item.fields[$0] }
            if was.track != now.track { fields.insert("track") }
            if !fields.isEmpty { modified.append((id, fields.sorted())) }
        }
        let oldTracks = Dictionary(before.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newTracks = Dictionary(after.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let trackFields = { (track: Track) in track.fields.filter { $0.key != "items" } }
        let tracks: [String: JSONValue] = [
            "added": .array(newTracks.keys.filter { oldTracks[$0] == nil }.sorted().map(JSONValue.string)),
            "removed": .array(oldTracks.keys.filter { newTracks[$0] == nil }.sorted().map(JSONValue.string)),
            "modified": .array(newTracks.keys.filter { id in
                oldTracks[id].map { trackFields($0) != trackFields(newTracks[id]!) } ?? false
            }.sorted().map(JSONValue.string)),
        ]
        let skip: Set<String> = ["tracks", "rev"]
        let projectFields = Set(before.fields.keys).union(after.fields.keys).subtracting(skip)
            .filter { before.fields[$0] != after.fields[$0] }.sorted()
        let truncated = added.count > limit || removed.count > limit || modified.count > limit
        var lines = added.prefix(limit).map { "+ \($0) on \(new[$0]?.track ?? "")" }
        lines += modified.prefix(limit).map { "~ \($0.0) \($0.1.joined(separator: ","))" }
        lines += removed.prefix(limit).map { "- \($0)" }
        lines += projectFields.map { "~ project.\($0)" }
        return .object([
            "added": .array(added.prefix(limit).map { id in
                .object(["id": .string(id), "track": .string(new[id]?.track ?? ""), "at": .integer(new[id]?.item.at ?? 0),
                         "dur": .integer(new[id]?.item.duration ?? 0)])
            }),
            "removed": .array(removed.prefix(limit).map(JSONValue.string)),
            "modified": .array(modified.prefix(limit).map { .object(["id": .string($0.0), "fields": .array($0.1.map(JSONValue.string))]) }),
            "counts": .object(["added": .integer(added.count), "removed": .integer(removed.count), "modified": .integer(modified.count)]),
            "tracks": .object(tracks), "project": .array(projectFields.map(JSONValue.string)),
            "duration": .object(["before": .integer(before.duration), "after": .integer(after.duration)]),
            "truncated": .bool(truncated), "text": .string(lines.joined(separator: "\n")),
        ])
    }
}
