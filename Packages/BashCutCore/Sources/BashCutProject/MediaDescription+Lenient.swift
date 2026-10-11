import Foundation

/// Shots as a describer actually writes them (a sub-agent's notes): numbers given as text ("659.0 s"), subjects as one
/// comma-separated string, labels and notes over their length, a best moment or looked frames just outside the shot,
/// shots that overlap where one ends. Each is repaired the obvious way and reported in `adjusted`, so a description
/// lands in one call; what cannot be repaired (no start and end, nothing described) is reported for every shot at
/// once instead of the first only.
extension MediaDescription {
    public static func lenientShots(_ rows: [JSONValue], duration: Double) throws -> (shots: [Shot], adjusted: [String]) {
        guard (1...maximumShots).contains(rows.count) else {
            throw ProjectError.invalid("description.shots: expected 1–\(maximumShots) shots")
        }
        var adjusted: [String] = []
        var errors: [String] = []
        var shots: [Shot] = []
        for (index, row) in rows.enumerated() {
            let (fields, notes) = repaired(row, at: index, duration: duration)
            adjusted += notes
            do { shots.append(try shot(.object(fields), at: index, duration: duration)) } catch {
                errors.append(error.localizedDescription)
            }
        }
        guard errors.isEmpty else { throw ProjectError.invalid(errors.prefix(20).joined(separator: "\n")) }
        shots.sort { $0.start < $1.start }
        var kept: [Shot] = []
        for var shot in shots {
            if var previous = kept.last, shot.start < previous.end - 0.001 {
                if shot.start - previous.start >= 0.1 {
                    adjusted.append(String(
                        format: "shot %.3f–%.3f s ended at %.3f s where the next shot starts", previous.start,
                        previous.end, shot.start))
                    previous.end = shot.start
                    previous.clip()
                    kept[kept.count - 1] = previous
                } else if shot.end - previous.end >= 0.1 {
                    adjusted.append(String(
                        format: "shot %.3f–%.3f s starts at %.3f s where the one before ends", shot.start, shot.end,
                        previous.end))
                    shot.start = previous.end
                    shot.clip()
                } else {
                    errors.append(String(
                        format: "description.shots: %.3f–%.3f s lies inside %.3f–%.3f s", shot.start, shot.end,
                        previous.start, previous.end))
                    continue
                }
            }
            kept.append(shot)
        }
        guard errors.isEmpty else { throw ProjectError.invalid(errors.prefix(20).joined(separator: "\n")) }
        return (kept, Array(adjusted.prefix(30)))
    }

    /// The first number in a number or a text such as "659.0 s" or "~12".
    static func number(in value: JSONValue?) -> Double? {
        if let number = value?.double { return number }
        guard let text = value?.string, let range = text.range(of: #"-?\d+(\.\d+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(text[range])
    }

    private static func repaired(_ row: JSONValue, at index: Int, duration: Double) -> ([String: JSONValue], [String]) {
        guard case .object(var fields) = row else { return ([:], []) }
        let path = "shots[\(index)]"
        var notes: [String] = []
        repairEdges(&fields, path: path, duration: duration, notes: &notes)
        repairNames(&fields, path: path, notes: &notes)
        repairFacts(&fields, path: path, notes: &notes)
        repairMoments(&fields, path: path, notes: &notes)
        return (fields, notes)
    }

    /// Start and end as numbers; an end past the media cut to its length.
    private static func repairEdges(_ fields: inout [String: JSONValue], path: String, duration: Double, notes: inout [String]) {
        for key in ["start", "end"] where fields[key]?.double == nil {
            if let number = number(in: fields[key]) { fields[key] = .number(number) }
        }
        if let end = fields["end"]?.double, let start = fields["start"]?.double, start < duration, end > duration + 0.05 {
            fields["end"] = .number(duration)
            notes.append(String(format: "%@.end cut to the media's %.3f s", path, duration))
        }
    }

    /// Subjects and tags as lists of short names (a comma-separated string split).
    private static func repairNames(_ fields: inout [String: JSONValue], path: String, notes: inout [String]) {
        for (key, limit) in [("subjects", 12), ("tags", 50)] {
            guard let value = fields[key], value != .null else { continue }
            let given: [String] = value.string.map { text in
                text.split(whereSeparator: { ",;".contains($0) }).map(String.init)
            } ?? value.array.map { $0.string ?? number(in: $0).map { String($0) } ?? "" }
            var names = given.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if names.contains(where: { $0.count > 60 }) || names.count > limit || value.string != nil {
                names = names.prefix(limit).map { String($0.prefix(60)) }
                notes.append("\(path).\(key) as \(names.count) names of at most 60 characters")
            }
            fields[key] = .array(names.map(JSONValue.string))
        }
    }

    /// Labels and the note within their length; people and confidence as numbers (a percentage as a share).
    private static func repairFacts(_ fields: inout [String: JSONValue], path: String, notes: inout [String]) {
        for key in ["size", "angle", "move", "direction"] {
            guard let label = fields[key]?.string else { continue }
            let trimmed = label.trimmingCharacters(in: .whitespaces)
            fields[key] = trimmed.isEmpty ? nil : .string(String(trimmed.prefix(60)))
        }
        if let note = fields["note"]?.string, note.count > 300 {
            fields["note"] = .string(String(note.prefix(299)) + "…")
            notes.append("\(path).note cut to 300 characters")
        }
        if let value = fields["people"], value != .null, value.int == nil {
            fields["people"] = number(in: value).map { .integer(Int($0.rounded())) }
        }
        if let value = fields["confidence"], value != .null {
            fields["confidence"] = number(in: value).map { .number($0 > 1 && $0 <= 100 ? $0 / 100 : $0) }
        }
    }

    /// The best moment moved inside the shot; looked frames outside it dropped.
    private static func repairMoments(_ fields: inout [String: JSONValue], path: String, notes: inout [String]) {
        let start = fields["start"]?.double ?? 0, end = fields["end"]?.double ?? 0
        if let value = fields["bestMoment"], value != .null {
            if let seconds = number(in: value), seconds.isFinite {
                let clamped = min(max(seconds, start), end)
                if clamped != seconds { notes.append(String(format: "%@.bestMoment %.3f s moved inside the shot", path, seconds)) }
                fields["bestMoment"] = .number(clamped)
            } else {
                fields["bestMoment"] = nil
                notes.append("\(path).bestMoment dropped: not source seconds")
            }
        }
        guard let value = fields["looked"], value != .null else { return }
        let given: [Double] = value.array.isEmpty
            ? (value.string ?? "").split(whereSeparator: { ", ;".contains($0) }).compactMap { Double($0) }
            : value.array.compactMap { number(in: $0) }
        let kept = given.filter { $0.isFinite && $0 >= start - 0.001 && $0 <= end + 0.001 }.prefix(50)
        if kept.count != given.count || value.string != nil {
            notes.append("\(path).looked keeps \(kept.count) of \(given.count) seconds inside the shot")
        }
        fields["looked"] = .array(kept.map(JSONValue.number))
    }
}

extension MediaDescription.Shot {
    /// Keeps the best moment and looked frames inside the shot after its edges moved.
    mutating func clip() {
        if let moment = bestMoment { bestMoment = min(max(moment, start), end) }
        looked = looked.filter { $0 >= start - 0.001 && $0 <= end + 0.001 }
    }
}
