import Foundation

/// The known name a mistyped one most likely meant, for "did you mean" hints in errors (#628).
enum NearestName {
    /// Edits (insertions, deletions, substitutions) between `a` and `b`, ignoring case.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a.lowercased()), b = Array(b.lowercased())
        var row = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var next = [i + 1]
            for (j, cb) in b.enumerated() { next.append(min(row[j + 1] + 1, next[j] + 1, row[j] + (ca == cb ? 0 : 1))) }
            row = next
        }
        return row[b.count]
    }

    /// The candidate fewest edits away (ties by name), when it is within a third of `name`'s length (at least two):
    /// `setItemProperties` → `setProperties`.
    static func nearest(_ name: String, in candidates: [String]) -> String? {
        let limit = max(2, name.count / 3)
        let scored = candidates.map { ($0, distance(name, $0)) }.filter { $0.1 <= limit }
        return scored.min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }?.0
    }
}
