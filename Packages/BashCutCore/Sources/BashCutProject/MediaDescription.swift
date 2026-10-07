import Foundation

/// What the agent (or the user) saw in a source media, shot by shot (P0-A4): facts as open strings (the lists below
/// are a suggested vocabulary), free `tags` and any other fields, stored on the media in the project so they survive
/// save and reopen and travel with the project. Core only checks the time ranges and the value types. It never
/// pairs shots or judges them: there is no field for "cuts well to".
public struct MediaDescription: Sendable, Equatable {
    public static let maximumShots = 5_000

    /// Shot size, widest last: extreme close-up to extreme wide, plus an insert (a detail cut in).
    public static let sizes = ["ECU", "CU", "MCU", "MS", "MWS", "WS", "EWS", "insert"]
    public static let angles = ["eye", "high", "low", "top", "dutch", "pov", "ots"]
    public static let moves = ["static", "pan", "tilt", "push", "pull", "track", "orbit", "handheld", "zoom", "crane"]
    /// Where the subject moves on screen.
    public static let directions = ["left", "right", "toward", "away", "none"]

    public struct Shot: Sendable, Equatable {
        /// Source seconds.
        public var start: Double
        public var end: Double
        public var size: String?
        public var angle: String?
        public var move: String?
        public var direction: String?
        public var subjects: [String]
        public var people: Int?
        public var onScreenText: Bool?
        /// How sure the describer is of these facts, 0–1.
        public var confidence: Double?
        /// Source seconds of the best moment in the shot, when there is one.
        public var bestMoment: Double?
        /// Source seconds of the frames that were looked at.
        public var looked: [Double]
        public var note: String?
        /// Free labels.
        public var tags: [String] = []
        /// Any other fields the describer sent, kept as given.
        public var extra: [String: JSONValue] = [:]

        public var seconds: Double { end - start }
    }

    public var shots: [Shot]
    /// `Author` raw value of whoever wrote it.
    public var describedBy: String
    public var describedAt: String

    public init(shots: [Shot], describedBy: String, describedAt: String) {
        self.shots = shots.sorted { $0.start < $1.start }
        self.describedBy = describedBy
        self.describedAt = describedAt
    }

    /// The description stored on a media, checked against the vocabulary and the media's length in seconds.
    public init(json value: JSONValue, duration: Double) throws {
        let fields = value.object
        guard let rows = fields["shots"]?.array else { throw ProjectError.invalid("description.shots: expected array") }
        shots = try Self.shots(rows, duration: duration)
        describedBy = fields["describedBy"]?.string ?? Author.agent.rawValue
        describedAt = fields["describedAt"]?.string ?? ""
    }

    /// Shots as an agent sends them, checked against the vocabulary and the media's length, sorted by start; they
    /// may not overlap.
    public static func shots(_ rows: [JSONValue], duration: Double) throws -> [Shot] {
        guard (1...maximumShots).contains(rows.count) else {
            throw ProjectError.invalid("description.shots: expected 1–\(maximumShots) shots")
        }
        let shots = try rows.enumerated().map { index, row in try shot(row, at: index, duration: duration) }
            .sorted { $0.start < $1.start }
        for (previous, next) in zip(shots, shots.dropFirst()) where next.start < previous.end - 0.001 {
            throw ProjectError.invalid(String(
                format: "description.shots: %.3f–%.3f s overlaps %.3f–%.3f s", next.start, next.end, previous.start,
                previous.end))
        }
        return shots
    }

    private static let shotKeys = [
        "start", "end", "size", "angle", "move", "direction", "subjects", "people", "onScreenText", "confidence",
        "bestMoment", "looked", "note", "tags",
    ]

    private static func shot(_ value: JSONValue, at index: Int, duration: Double) throws -> Shot {
        let path = "description.shots[\(index)]"
        let fields = value.object
        guard case .object = value else { throw ProjectError.invalid("\(path): expected object") }
        guard let start = fields["start"]?.double, let end = fields["end"]?.double, start.isFinite, end.isFinite,
            start >= 0, end > start, end <= duration + 0.05
        else {
            throw ProjectError.invalid(String(format: "%@: start and end must be source seconds inside 0–%.3f", path,
                                              duration))
        }
        let inside = { (seconds: Double) in seconds.isFinite && seconds >= start - 0.001 && seconds <= end + 0.001 }
        var shot = Shot(
            start: start, end: min(end, duration + 0.05), subjects: [], looked: [])
        shot.size = try label(fields["size"], "\(path).size")
        shot.angle = try label(fields["angle"], "\(path).angle")
        shot.move = try label(fields["move"], "\(path).move")
        shot.direction = try label(fields["direction"], "\(path).direction")
        shot.tags = try read(fields["tags"], "\(path).tags: up to 50 labels of 1–60 characters") { value in
            let names = value.array.compactMap(\.string)
            guard case .array(let values) = value, names.count == values.count, names.count <= 50,
                names.allSatisfy({ (1...60).contains($0.count) })
            else { return nil }
            return names
        } ?? []
        shot.extra = fields.filter { !shotKeys.contains($0.key) }
        shot.subjects = try read(fields["subjects"], "\(path).subjects: up to 12 names of 1–60 characters") { value in
            let names = value.array.compactMap(\.string).map { $0.trimmingCharacters(in: .whitespaces) }
            guard case .array(let values) = value, names.count == values.count, names.count <= 12,
                names.allSatisfy({ (1...60).contains($0.count) })
            else { return nil }
            return names
        } ?? []
        shot.people = try read(fields["people"], "\(path).people: expected 0–1000") { value in
            value.int.flatMap { (0...1_000).contains($0) ? $0 : nil }
        }
        shot.onScreenText = try read(fields["onScreenText"], "\(path).onScreenText: expected boolean") { value in
            if case .bool(let flag) = value { flag } else { nil }
        }
        shot.confidence = try read(fields["confidence"], "\(path).confidence: expected 0–1") { value in
            value.double.flatMap { (0...1).contains($0) ? $0 : nil }
        }
        shot.bestMoment = try read(fields["bestMoment"], "\(path).bestMoment: expected source seconds inside the shot") {
            $0.double.flatMap { inside($0) ? $0 : nil }
        }
        shot.looked = try read(fields["looked"], "\(path).looked: up to 50 source seconds inside the shot") { value in
            let list = value.array.compactMap(\.double)
            guard case .array(let values) = value, list.count == values.count, list.count <= 50, list.allSatisfy(inside)
            else { return nil }
            return list.sorted()
        } ?? []
        shot.note = try read(fields["note"], "\(path).note: up to 300 characters") { value in
            value.string.flatMap { $0.count <= 300 ? $0 : nil }
        }
        let facts: [Any?] = [shot.size, shot.angle, shot.move, shot.direction, shot.people, shot.onScreenText,
                             shot.bestMoment, shot.note]
        guard facts.contains(where: { $0 != nil }) || !shot.subjects.isEmpty || !shot.tags.isEmpty || !shot.extra.isEmpty
        else {
            throw ProjectError.invalid("\(path): describe at least one fact")
        }
        return shot
    }

    /// nil when the field is missing or null; otherwise `parse` must accept it.
    private static func read<Value>(
        _ value: JSONValue?, _ message: String, _ parse: (JSONValue) -> Value?
    ) throws -> Value? {
        guard let value, value != .null else { return nil }
        guard let parsed = parse(value) else { throw ProjectError.invalid(message) }
        return parsed
    }

    /// An open label of 1–60 characters (the vocabulary lists are suggestions).
    private static func label(_ value: JSONValue?, _ path: String) throws -> String? {
        try read(value, "\(path): expected a label of 1–60 characters") { value in
            value.string.flatMap { (1...60).contains($0.count) ? $0 : nil }
        }
    }

    /// Replaces the shots that overlap any of `shots` and keeps the others.
    public func merging(_ new: [Shot]) throws -> [Shot] {
        let kept = shots.filter { old in !new.contains { $0.start < old.end - 0.001 && old.start < $0.end - 0.001 } }
        let merged = (kept + new).sorted { $0.start < $1.start }
        guard merged.count <= Self.maximumShots else {
            throw ProjectError.invalid("description.shots: expected 1–\(Self.maximumShots) shots")
        }
        return merged
    }

    /// The shots that overlap `start…end` source seconds.
    public func shots(from start: Double, to end: Double) -> [Shot] {
        shots.filter { $0.start < end && start < $0.end }
    }

    /// The shot covering most of `start…end` source seconds, if any overlaps it.
    public func shot(covering start: Double, to end: Double) -> Shot? {
        shots(from: start, to: end).max { overlap($0, start, end) < overlap($1, start, end) }
    }

    private func overlap(_ shot: Shot, _ start: Double, _ end: Double) -> Double {
        min(shot.end, end) - max(shot.start, start)
    }

    /// Seconds described, overlaps counted once (shots never overlap).
    public var describedSeconds: Double { shots.reduce(0) { $0 + $1.seconds } }

    /// How much of the media the description covers. With measured shots (`media.analyze`), a measured shot counts as
    /// described when described shots cover at least half of it; `missing` lists the others.
    public func coverage(duration: Double, measured: [(start: Double, end: Double)]?) -> JSONValue {
        var result: [String: JSONValue] = [
            "shots": .integer(shots.count), "describedSeconds": Self.number(describedSeconds),
            "describedShare": Self.number(duration > 0 ? min(1, describedSeconds / duration) : 0),
        ]
        guard let measured else { return .object(result) }
        var missing: [JSONValue] = []
        for (index, span) in measured.enumerated() {
            let covered = shots(from: span.start, to: span.end).reduce(0) { $0 + overlap($1, span.start, span.end) }
            if covered < (span.end - span.start) / 2 {
                missing.append(.object([
                    "index": .integer(index), "start": Self.number(span.start), "end": Self.number(span.end),
                ]))
            }
        }
        result["measuredShots"] = .integer(measured.count)
        result["coveredShots"] = .integer(measured.count - missing.count)
        result["missing"] = .array(missing)
        return .object(result)
    }

    public var json: JSONValue {
        .object([
            "shots": .array(shots.map(\.json)), "describedBy": .string(describedBy),
            "describedAt": .string(describedAt),
        ])
    }

    /// `{shots, describedBy, describedAt}` for lists that should not carry every shot.
    public var summaryJSON: JSONValue {
        .object([
            "shots": .integer(shots.count), "describedBy": .string(describedBy), "describedAt": .string(describedAt),
        ])
    }

    static func number(_ value: Double) -> JSONValue { .number((value * 1_000).rounded() / 1_000) }

    /// The suggested vocabulary, for `media.describe` callers and the schema; any other label is accepted.
    public static var vocabularyJSON: JSONValue {
        .object([
            "size": .array(sizes.map(JSONValue.string)), "angle": .array(angles.map(JSONValue.string)),
            "move": .array(moves.map(JSONValue.string)), "direction": .array(directions.map(JSONValue.string)),
        ])
    }
}

extension MediaDescription.Shot {
    public var json: JSONValue {
        var row = extra
        row["start"] = MediaDescription.number(start)
        row["end"] = MediaDescription.number(end)
        if !tags.isEmpty { row["tags"] = .array(tags.map(JSONValue.string)) }
        if let size { row["size"] = .string(size) }
        if let angle { row["angle"] = .string(angle) }
        if let move { row["move"] = .string(move) }
        if let direction { row["direction"] = .string(direction) }
        if !subjects.isEmpty { row["subjects"] = .array(subjects.map(JSONValue.string)) }
        if let people { row["people"] = .integer(people) }
        if let onScreenText { row["onScreenText"] = .bool(onScreenText) }
        if let confidence { row["confidence"] = MediaDescription.number(confidence) }
        if let bestMoment { row["bestMoment"] = MediaDescription.number(bestMoment) }
        if !looked.isEmpty { row["looked"] = .array(looked.map(MediaDescription.number)) }
        if let note { row["note"] = .string(note) }
        return .object(row)
    }

    /// The facts without timing, for views that place the shot elsewhere (`review.shots`).
    public var factsJSON: JSONValue {
        var row = json.object
        for key in ["start", "end", "looked", "note"] { row[key] = nil }
        return .object(row)
    }
}

extension Media {
    /// The stored description, when it reads; an invalid one is rejected by validation before it can be stored.
    public var shotDescription: MediaDescription? {
        guard let value = fields["description"], value != .null else { return nil }
        return try? MediaDescription(json: value, duration: durationSeconds)
    }
}
