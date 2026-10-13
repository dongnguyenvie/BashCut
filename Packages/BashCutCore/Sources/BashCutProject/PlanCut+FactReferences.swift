import Foundation

/// Fact references (P3-I4): any `plan.cut` entry may give `facts: [key]`, the project facts (`knowledge set-fact`)
/// or claims (`knowledge set-claim`) its words or picture rest on. `plan check` lists a key that is neither, so a
/// typo or a fact never recorded is caught before the edit is built; it judges nothing about the fact itself.
extension PlanCut {
    /// Each entry's `facts`, in list order; entries without one are left out.
    static func factReferences(_ lists: [([JSONValue], [String])]) throws -> [(entry: String, keys: [String])] {
        try lists.flatMap { values, ids in
            try zip(values, ids).compactMap { value, id -> (entry: String, keys: [String])? in
                guard let given = value.object["facts"], given != .null else { return nil }
                guard case .array(let list) = given, let keys = Optional(list.compactMap(\.string)), keys.count == list.count
                else {
                    throw ProjectError.invalid("\(id): facts must be a list of fact keys [\"key\", …]")
                }
                return keys.isEmpty ? nil : (id, keys)
            }
        }
    }

    /// An `unknown-fact` warning per entry that cites keys `known` (the project's fact and claim keys) lacks.
    public static func factProblems(_ spec: Spec, known: Set<String>) -> [Problem] {
        spec.factReferences.compactMap { entry, keys in
            let missing = keys.filter { !known.contains($0) }
            guard !missing.isEmpty else { return nil }
            return Problem(
                id: "unknown-fact", severity: "warning", entry: entry,
                detail: "Cites \(missing.joined(separator: ", ")), not a fact or claim of this project: record it "
                    + "(knowledge set-fact KEY VALUE --source …, or knowledge set-claim) or fix the key",
                facts: ["keys": .array(missing.map(JSONValue.string)), "known": .integer(known.count)])
        }
    }
}
