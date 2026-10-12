import Foundation

extension PlanCut {
    /// `plan.check --patch` / `plan.apply --patch`: `patch` merged over the edit list, so a revision names only
    /// what changes. Objects merge key by key (null removes the key). A list of entries with `id` (clips, titles)
    /// takes an object keyed by ID: each value merges into that entry, null removes it, an unknown ID adds an entry
    /// at the end (in ID order). Anything else replaces the value.
    public static func patch(_ list: JSONValue, with patch: JSONValue) throws -> JSONValue {
        guard case .object = list else { throw ProjectError.invalid("plan.cut must be an object to patch") }
        guard case .object = patch else { throw ProjectError.invalid("patch must be an object, such as {clips: {c2: {from: 12}}}") }
        return merge(list, patch)
    }

    static func merge(_ value: JSONValue, _ patch: JSONValue) -> JSONValue {
        switch (value, patch) {
        case (.object(let fields), .object(let changes)):
            return .object(mergeFields(fields, changes))
        case (.array(let entries), .object(let byID)) where entries.allSatisfy({ $0.object["id"]?.string != nil }):
            return .array(mergeEntries(entries, byID))
        default:
            return stripNulls(patch)
        }
    }

    static func mergeFields(_ fields: [String: JSONValue], _ changes: [String: JSONValue]) -> [String: JSONValue] {
        var fields = fields
        for (key, change) in changes {
            if change == .null {
                fields.removeValue(forKey: key)
            } else {
                fields[key] = fields[key].map { merge($0, change) } ?? stripNulls(change)
            }
        }
        return fields
    }

    static func mergeEntries(_ entries: [JSONValue], _ byID: [String: JSONValue]) -> [JSONValue] {
        var entries = entries
        for (id, change) in byID.sorted(by: { $0.key < $1.key }) {
            let index = entries.firstIndex { $0.object["id"]?.string == id }
            switch (index, change) {
            case (let index?, .null): entries.remove(at: index)
            case (let index?, _): entries[index] = merge(reselected(entries[index], by: change), change)
            case (nil, .object(var fields)):
                fields["id"] = .string(id)
                entries.append(stripNulls(.object(fields)))
            default: break
            }
        }
        return entries
    }

    /// A clip patched with a new quote or words is picked by that alone: its old quote, words and from/to go,
    /// unless the patch gives them too (from/to then move the new range's edges).
    static func reselected(_ entry: JSONValue, by change: JSONValue) -> JSONValue {
        guard case .object(var fields) = entry, case .object(let changes) = change,
            changes["quote"] != nil || changes["words"] != nil
        else { return entry }
        for key in ["quote", "words", "from", "to"] where changes[key] == nil { fields.removeValue(forKey: key) }
        return .object(fields)
    }

    /// A new value with the null members of its objects left out (a patch's null means "remove", never "store null").
    static func stripNulls(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let fields): .object(fields.filter { $0.value != .null }.mapValues(stripNulls))
        case .array(let entries): .array(entries.map(stripNulls))
        default: value
        }
    }
}
