import Foundation

/// `patchItems` (restyle): one wire op that deep-merges a patch into many items, expanded against the project into
/// plain `setProperties` ops before the edit runs, so undo, dry run, scope and fingerprints see ordinary ops.
///
/// `{"op":"patchItems", "items":["ID",…] | "select":{track, trackRole, trackKind, textPreset, media}, "patch":{…}}`:
/// object fields (`textStyle`, `transform`, `color`, `wordStyle`…) merge key by key at every depth, `null` deletes a
/// key, anything else (arrays, numbers, text) replaces. Every selector field given must match.
public enum ItemPatch {
    public static let op = "patchItems"

    /// `ops` with every `patchItems` replaced by one `setProperties` per selected item. Earlier ops of the same batch
    /// that set item properties are merged into the base, so two restyles in one batch compose.
    public static func expand(_ ops: [JSONValue], in project: Project) throws -> [JSONValue] {
        var pending: [String: [String: JSONValue]] = [:]
        let items = Dictionary(
            project.tracks.flatMap { track in track.items.map { ($0.id, ($0, track)) } }, uniquingKeysWith: { first, _ in first })
        var result: [JSONValue] = []
        for op in ops {
            let fields = op.object
            switch fields["op"]?.string {
            case "patchItems":
                guard case .object(let patch)? = fields["patch"], !patch.isEmpty else {
                    throw ProjectError.invalid("patchItems: give a nonempty patch object")
                }
                let ids = try select(fields, items: items, order: project.tracks.flatMap { $0.items.map(\.id) })
                for id in ids {
                    let current = pending[id] ?? items[id]?.0.fields ?? [:]
                    var change: [String: JSONValue] = [:]
                    for (key, value) in patch {
                        change[key] = merge(current[key], value)
                    }
                    pending[id, default: current].merge(change) { $1 }
                    result.append(.object(["op": .string("setProperties"), "item": .string(id), "patch": .object(change)]))
                }
            case "setProperties":
                if let id = fields["item"]?.string, case .object(let patch)? = fields["patch"] {
                    pending[id, default: items[id]?.0.fields ?? [:]].merge(patch) { $1 }
                }
                result.append(op)
            default:
                result.append(op)
            }
        }
        return result
    }

    /// `patch` merged into `base`: objects key by key (null deletes), anything else replaces. A top-level null stays
    /// null so `setProperties` removes the field.
    static func merge(_ base: JSONValue?, _ patch: JSONValue) -> JSONValue {
        guard case .object(let changes) = patch, case .object(var current)? = base else { return strip(patch) }
        for (key, value) in changes {
            if value == .null { current.removeValue(forKey: key) } else { current[key] = merge(current[key], value) }
        }
        return .object(current)
    }

    /// A new object without its null keys.
    private static func strip(_ value: JSONValue) -> JSONValue {
        guard case .object(let fields) = value else { return value }
        return .object(fields.filter { $0.value != .null }.mapValues(strip))
    }

    private static func select(
        _ fields: [String: JSONValue], items: [String: (Item, Track)], order: [String]
    ) throws -> [String] {
        if let list = fields["items"]?.array {
            let ids = list.compactMap(\.string)
            guard !ids.isEmpty, ids.count == list.count else { throw ProjectError.invalid("patchItems.items: expected item IDs") }
            if let missing = ids.first(where: { items[$0] == nil }) { throw ProjectError.invalid("Unknown item: \(missing)") }
            return ids
        }
        guard case .object(let selector)? = fields["select"], !selector.isEmpty else {
            throw ProjectError.invalid("patchItems: give items or select")
        }
        let known: Set<String> = ["track", "trackRole", "trackKind", "textPreset", "media"]
        if let unknown = selector.keys.sorted().first(where: { !known.contains($0) }) {
            throw ProjectError.invalid("patchItems.select: unknown key \(unknown) (use \(known.sorted().joined(separator: ", ")))")
        }
        let wanted = selector.compactMapValues(\.string)
        let ids = order.filter { id in
            guard let (item, track) = items[id] else { return false }
            let actual: [String: String?] = [
                "track": track.id, "trackRole": track.role, "trackKind": track.kind, "textPreset": item.textPreset,
                "media": item.mediaID,
            ]
            return wanted.allSatisfy { (actual[$0.key] ?? nil) == $0.value }
        }
        guard !ids.isEmpty else { throw ProjectError.invalid("patchItems.select matched no items") }
        return ids
    }
}
